namespace MajorisFiles {
    public class CloudAccounts : Object {
        public Gee.ArrayList<Place> entries = new Gee.ArrayList<Place>();
        public signal void changed();
        CloudProviders.Collector? collector;
        ulong collector_handler;
        Gee.HashMap<Object, ulong?> handlers = new Gee.HashMap<Object, ulong?>();
        public CloudAccounts()
        {
            if(Environment.get_variable("DBUS_SESSION_BUS_ADDRESS") == null)
                return;
            collector = CloudProviders.Collector.dup_singleton();
            collector_handler = collector.providers_changed.connect(refresh);
            refresh();
        }
        void refresh()
        {
            foreach(var object in handlers.keys)
                object.disconnect(handlers[object]);
            handlers.clear();
            entries.clear();
            foreach(var provider in collector.get_providers())
            {
                handlers[provider] = provider.accounts_changed.connect(refresh);
                foreach(var account in provider.get_accounts())
                {
                    handlers[account] = account.notify.connect(refresh);
                    string? path = account.get_path(), name = account.get_name();
                    if(path == null || !Path.is_absolute(path) || name == null || account.get_status() == CloudProviders.AccountStatus.INVALID)
                        continue;
                    string status = account.get_status() == CloudProviders.AccountStatus.SYNCING ? "Syncing" : account.get_status() == CloudProviders.AccountStatus.ERROR ? "Sync Error" : "Up to Date";
                    var place = new Place((provider.get_name() ?? "Cloud") + ": " + name + " · " + status, File.new_for_path(path));
                    place.cloud = account;
                    entries.add(place);
                }
            }
            changed();
        }
        protected override void dispose()
        {
            if(collector != null && collector_handler != 0)
                collector.disconnect(collector_handler);
            collector_handler = 0;
            foreach(var object in handlers.keys)
                object.disconnect(handlers[object]);
            handlers.clear();
            base.dispose();
        }
    }
}
