namespace MajorisFiles {
    public class PortalApplication : Adw.Application {
        PortalBackend? backend;
        uint owner;
        public PortalApplication()
        {
            Object(application_id: "com.majoris.files.portal", flags: ApplicationFlags.IS_SERVICE);
        }
        protected override void startup()
        {
            base.startup();
            hold();
            owner = Bus.own_name(BusType.SESSION, "org.freedesktop.impl.portal.desktop.majoris", BusNameOwnerFlags.NONE, (connection) => { try { backend = new PortalBackend(connection, this);
                                                                                                                                                 connection.register_object("/org/freedesktop/portal/desktop", backend);
                                                                                                                                           }
                                                                                                                                           catch (Error e) { critical("Portal registration failed: %s", e.message);
                                                                                                                                                             quit();
                                                                                                                                           }
                }, null, () => quit());
        }
        protected override void shutdown()
        {
            Bus.unown_name(owner);
            base.shutdown();
        }
    }
}
int main(string[] args)
{
    return new MajorisFiles.PortalApplication().run(args);
}
