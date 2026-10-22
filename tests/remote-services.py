#!/usr/bin/python3
"""Disposable loopback SFTP and WebDAV services; never opens a public listener.

Run in a private network namespace, as the normal test user. Requires Debian's
python3-paramiko and gvfs-backends. Does not configure a host SSH/DAV server.
"""
import contextlib, errno, http.server, os, pathlib, secrets, socket, subprocess
import sys, tempfile, threading, time, urllib.parse, xml.etree.ElementTree as ET
import paramiko
import logging
logging.basicConfig(level=logging.INFO)

if os.readlink('/proc/self/ns/net') == os.readlink('/proc/1/ns/net'):
    raise SystemExit('Use a private network namespace for this fixture')
if os.geteuid() == 0:
    uid=int(os.environ.get('MAJORIS_TEST_UID','1000'))
    if uid<=0: raise SystemExit('Fixture clients must be unprivileged')
    os.setgroups([]);os.setgid(uid);os.setuid(uid)
ROOT = None
PASSWORD = secrets.token_urlsafe(32)

def path(name):
    value = ROOT / urllib.parse.unquote(name).lstrip('/')
    resolved = value.resolve()
    if not resolved.is_relative_to(ROOT):
        raise PermissionError('Outside fixture')
    return resolved

class Auth(paramiko.ServerInterface):
    def check_auth_password(self, username, password):
        return paramiko.AUTH_SUCCESSFUL if username == 'fixture' and secrets.compare_digest(password, PASSWORD) else paramiko.AUTH_FAILED
    def get_allowed_auths(self, username): return 'password'
    def check_channel_request(self, kind, channel_id):
        return paramiko.OPEN_SUCCEEDED if kind == 'session' else paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED

def sftp_error(fn):
    def wrap(*args):
        try: return fn(*args)
        except OSError as exc: return paramiko.SFTPServer.convert_errno(exc.errno or errno.EACCES)
    return wrap

class SFTP(paramiko.SFTPServerInterface):
    def __init__(self,server,*args,**kwargs):
        super().__init__(server,*args,**kwargs);self.transport=server.transport
    @sftp_error
    def list_folder(self, name):
        result=[]
        for item in path(name).iterdir():
            attrs=paramiko.SFTPAttributes.from_stat(item.stat());attrs.filename=item.name;result.append(attrs)
        return result
    @sftp_error
    def stat(self, name): return paramiko.SFTPAttributes.from_stat(path(name).stat())
    lstat=stat
    @sftp_error
    def open(self, name, flags, attr):
        fd=os.open(path(name), flags, 0o600)
        mode='r+b' if flags & os.O_RDWR else 'wb' if flags & os.O_WRONLY else 'rb'
        class Handle(paramiko.SFTPHandle):
            def stat(handle): return paramiko.SFTPAttributes.from_stat(os.fstat(file.fileno()))
            def chattr(handle,attrs):
                paramiko.SFTPServer.set_file_attr(str(path(name)),attrs);return paramiko.SFTP_OK
            def read(handle,offset,length):
                if name.endswith('/disconnect.bin') and offset>=65536:
                    self.transport.close();return paramiko.SFTP_FAILURE
                return super(Handle,handle).read(offset,length)
        handle=Handle(flags);file=os.fdopen(fd, mode)
        if flags & (os.O_WRONLY|os.O_RDWR): handle.writefile=file
        if not flags & os.O_WRONLY: handle.readfile=file
        return handle
    @sftp_error
    def remove(self,name): path(name).unlink();return paramiko.SFTP_OK
    @sftp_error
    def rename(self,old,new):
        if path(new).exists(): return paramiko.SFTP_FAILURE
        path(old).rename(path(new));return paramiko.SFTP_OK
    @sftp_error
    def posix_rename(self,old,new):
        os.replace(path(old),path(new));return paramiko.SFTP_OK
    @sftp_error
    def mkdir(self,name,attr): path(name).mkdir();return paramiko.SFTP_OK
    @sftp_error
    def rmdir(self,name): path(name).rmdir();return paramiko.SFTP_OK
    @sftp_error
    def chattr(self,name,attr):
        paramiko.SFTPServer.set_file_attr(str(path(name)),attr);return paramiko.SFTP_OK

class DAV(http.server.BaseHTTPRequestHandler):
    protocol_version='HTTP/1.1'
    def log_message(self,*args): pass
    def respond(self,code,body=b'',headers=None):
        self.send_response(code)
        for key,value in (headers or {}).items(): self.send_header(key,str(value))
        self.send_header('Content-Length',str(len(body)));self.end_headers()
        if self.command!='HEAD': self.wfile.write(body)
    def do_OPTIONS(self): self.respond(200,headers={'DAV':'1, 2','Allow':'OPTIONS, PROPFIND, GET, HEAD, PUT, MOVE, COPY, DELETE, MKCOL'})
    def do_PROPFIND(self):
        self.rfile.read(int(self.headers.get('Content-Length','0')))
        target=path(self.path)
        if not target.exists(): return self.respond(404)
        ET.register_namespace('d','DAV:');root=ET.Element('{DAV:}multistatus')
        targets=[target]+(list(target.iterdir()) if target.is_dir() and self.headers.get('Depth')!='0' else [])
        for item in targets:
            response=ET.SubElement(root,'{DAV:}response');href='/'+str(item.relative_to(ROOT))
            if href=='/.': href='/'
            if item.is_dir() and not href.endswith('/'): href+='/'
            ET.SubElement(response,'{DAV:}href').text=urllib.parse.quote(href)
            ps=ET.SubElement(response,'{DAV:}propstat');prop=ET.SubElement(ps,'{DAV:}prop');kind=ET.SubElement(prop,'{DAV:}resourcetype')
            if item.is_dir(): ET.SubElement(kind,'{DAV:}collection')
            ET.SubElement(prop,'{DAV:}displayname').text=item.name
            ET.SubElement(prop,'{DAV:}getcontentlength').text=str(item.stat().st_size if item.is_file() else 0)
            ET.SubElement(prop,'{DAV:}getetag').text='"%s-%s"'%(item.stat().st_mtime_ns,item.stat().st_size)
            ET.SubElement(prop,'{DAV:}getlastmodified').text=self.date_time_string(item.stat().st_mtime)
            ET.SubElement(prop,'{DAV:}getcontenttype').text='httpd/unix-directory' if item.is_dir() else 'application/octet-stream'
            ET.SubElement(ps,'{DAV:}status').text='HTTP/1.1 200 OK'
        self.respond(207,ET.tostring(root,encoding='utf-8',xml_declaration=True),{'Content-Type':'application/xml'})
    def do_GET(self):
        target=path(self.path)
        if not target.is_file(): return self.respond(404)
        if target.name=='disconnect.bin' and self.command!='HEAD':
            self.send_response(200);self.send_header('Content-Length',str(target.stat().st_size));self.end_headers();self.wfile.write(target.read_bytes()[:65536]);self.wfile.flush();self.connection.shutdown(socket.SHUT_RDWR);self.connection.close();return
        self.respond(200,target.read_bytes(),{'Content-Type':'application/octet-stream','ETag':'"%s-%s"'%(target.stat().st_mtime_ns,target.stat().st_size)})
    do_HEAD=do_GET
    def do_PUT(self):
        target=path(self.path);existed=target.exists()
        if self.headers.get('If-None-Match')=='*' and existed: return self.respond(412)
        data=self.rfile.read(int(self.headers.get('Content-Length','0')))
        target.write_bytes(data);self.respond(204 if existed else 201)
    def do_MOVE(self):
        target=path(urllib.parse.urlsplit(self.headers['Destination']).path)
        if target.exists() and self.headers.get('Overwrite')=='F': return self.respond(412)
        path(self.path).rename(target);self.respond(201)
    def do_COPY(self):
        import shutil
        source=path(self.path);target=path(urllib.parse.urlsplit(self.headers['Destination']).path)
        if target.exists() and self.headers.get('Overwrite')=='F': return self.respond(412)
        if source.is_dir(): shutil.copytree(source,target)
        else: shutil.copyfile(source,target)
        self.respond(201)
    def do_DELETE(self):
        target=path(self.path)
        if target.is_dir(): target.rmdir()
        else: target.unlink()
        self.respond(204)
    def do_MKCOL(self): path(self.path).mkdir();self.respond(201)

def client(binary,uri,home):
    runtime=pathlib.Path(tempfile.mkdtemp(prefix='mr-'))
    env={**os.environ,'HOME':str(home),'USER':'administrator','LOGNAME':'administrator','XDG_DATA_DIRS':'/usr/local/share:/usr/share','XDG_RUNTIME_DIR':str(runtime),'XDG_CONFIG_HOME':str(home/'config'),'XDG_DATA_HOME':str(home/'data'),'XDG_CACHE_HOME':str(home/'cache'),'MAJORIS_FIXTURE_PASSWORD':PASSWORD,'GSK_RENDERER':'cairo','GSETTINGS_BACKEND':'memory','GVFS_DEBUG':'1'}
    env['MAJORIS_EXPECT_DISCONNECT']='1'
    env['GDK_BACKEND']='x11'
    if '--without-fuse' in sys.argv: env.update(GVFS_DISABLE_FUSE='1',MAJORIS_EXPECT_NO_FUSE='1')
    try: subprocess.run(['dbus-run-session','--','xvfb-run','-a',binary,uri],env=env,check=True,timeout=100)
    finally:
        import shutil
        mount=runtime/'gvfs'
        if os.path.ismount(mount):
            subprocess.run(['fusermount3','-u',str(mount)],check=True)
        if os.path.ismount(mount): raise RuntimeError('Refusing to remove a mounted GVfs fixture')
        shutil.rmtree(runtime,ignore_errors=True)

with tempfile.TemporaryDirectory(prefix='majoris-remote-services-') as directory:
    base=pathlib.Path(directory)
    for backend in ('sftp','dav'):
        ROOT=base/backend;ROOT.mkdir();(ROOT/'payload.txt').write_text('remote fixture\n');(ROOT/'large.bin').write_bytes(b'x'*(12*1024*1024));(ROOT/'disconnect.bin').write_bytes(b'x'*(12*1024*1024))
        home=base/(backend+'-home');home.mkdir()
        if backend=='dav':
            server=http.server.ThreadingHTTPServer(('127.0.0.1',0),DAV)
            threading.Thread(target=server.serve_forever,daemon=True).start()
            try: client(sys.argv[1],f'dav://127.0.0.1:{server.server_port}/',home)
            finally: server.shutdown();server.server_close()
        else:
            key=paramiko.RSAKey.generate(2048);listener=socket.socket();listener.bind(('127.0.0.1',0));listener.listen(8);transports=[]
            def accept():
                while True:
                    try: connection,_=listener.accept()
                    except OSError: return
                    transport=paramiko.Transport(connection);transports.append(transport)
                    transport.add_server_key(key);transport.set_subsystem_handler('sftp',paramiko.SFTPServer,SFTP)
                    auth=Auth();auth.transport=transport
                    try: transport.start_server(server=auth)
                    except (EOFError,paramiko.SSHException): transport.close()
            threading.Thread(target=accept,daemon=True).start()
            try: client(sys.argv[1],f'sftp://fixture@127.0.0.1:{listener.getsockname()[1]}/',home)
            finally:
                listener.close()
                for transport in transports: transport.close()
        print('PASS:',backend,'disposable-service acceptance',flush=True)
