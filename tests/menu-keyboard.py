"""Native Right/Left/Escape regression; pass the Majoris-Theme repository."""
import gi, subprocess, sys
from pathlib import Path
gi.require_version('Gtk','4.0')
from gi.repository import Gtk,Gio,GLib,Gdk
Gtk.init()
provider=Gtk.CssProvider();provider.load_from_path(str(Path(sys.argv[1]).resolve() / 'theme/Majoris/gtk-4.0/gtk.css'));Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(),provider,Gtk.STYLE_PROVIDER_PRIORITY_USER)
w=Gtk.Window(title='Arrowless keyboard fixture');m=Gio.Menu();sub=Gio.Menu();sub.append('Child','test.child');m.append_submenu('More Actions',sub)
g=Gio.SimpleActionGroup();g.add_action(Gio.SimpleAction.new('child',None));w.insert_action_group('test',g)
p=Gtk.PopoverMenu.new_from_model(m);p.set_has_arrow(False);b=Gtk.MenuButton();b.set_popover(p);w.set_child(b);w.present()
def settle():
 loop=GLib.MainLoop();GLib.timeout_add(150,lambda:(loop.quit(),False)[1]);loop.run()
def walk(w):
 yield w
 c=w.get_first_child()
 while c:yield from walk(c);c=c.get_next_sibling()
settle();subprocess.run(['xdotool','search','--name','^Arrowless keyboard fixture$','windowfocus','--sync'],check=True,stdout=subprocess.DEVNULL)
b.popup();settle();label=next(x for x in walk(p) if isinstance(x,Gtk.Label) and x.get_text()=='More Actions');label.get_parent().grab_focus()
subprocess.run(['xdotool','key','Right'],check=True);settle();assert any(isinstance(x,Gtk.Label) and x.get_text()=='Child' and x.get_mapped() for x in walk(p))
subprocess.run(['xdotool','key','Left'],check=True);settle();assert label.get_mapped()
subprocess.run(['xdotool','key','Escape'],check=True);settle();assert not p.get_visible()
print('Right/Left submenu navigation and Escape passed with arrowless Theme')
