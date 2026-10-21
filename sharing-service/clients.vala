namespace MajorisFiles {
    public class SharingClients : Object {
        static string text(Json.Object object, string key)
        {
            if (!object.has_member(key) || object.get_member(key).get_value_type() != typeof(string)) return "";
            string value = object.get_string_member(key);
            return value.length <= 512 ? value : "";
        }
        public static string filter(string json, string share) throws Error
        {
            var parser = new Json.Parser(); parser.load_from_data(json);
            if (parser.get_root().get_node_type() != Json.NodeType.OBJECT) throw new IOError.INVALID_DATA("Invalid Samba status response");
            var root = parser.get_root().get_object();
            var builder = new Json.Builder(); builder.begin_array();
            if (root.has_member("tcons") && root.get_member("tcons").get_node_type() == Json.NodeType.OBJECT &&
                root.has_member("sessions") && root.get_member("sessions").get_node_type() == Json.NodeType.OBJECT) {
                var connections = root.get_object_member("tcons"), sessions = root.get_object_member("sessions");
                int count = 0;
                foreach (var key in connections.get_members()) {
                    if (connections.get_member(key).get_node_type() != Json.NodeType.OBJECT) continue;
                    var connection = connections.get_object_member(key);
                    if (text(connection, "service") != share || count++ >= 256) continue;
                    string user = ""; string id = text(connection, "session_id");
                    if (sessions.has_member(id) && sessions.get_member(id).get_node_type() == Json.NodeType.OBJECT) user = text(sessions.get_object_member(id), "username");
                    builder.begin_object();
                    builder.set_member_name("client"); builder.add_string_value(text(connection, "machine"));
                    builder.set_member_name("user"); builder.add_string_value(user);
                    builder.set_member_name("share"); builder.add_string_value(share);
                    builder.set_member_name("status"); builder.add_string_value("Connected");
                    builder.end_object();
                }
            }
            builder.end_array(); var generator = new Json.Generator(); generator.set_root(builder.get_root()); return generator.to_data(null);
        }
    }
}
