namespace MajorisFiles {
    public class FileGroups : Object {
        public static string label(FileItem item, string mode, MetadataStore metadata)
        {
            if(mode == "Type")
                return item.directory ? "Folders" : ContentType.get_description(item.mime);
            if(mode == "Size")
            {
                if(item.directory)
                    return "Folders";
                if(item.bytes == 0)
                    return "Empty";
                if(item.bytes < 1024 * 1024)
                    return "Small · Under 1 MiB";
                if(item.bytes < 100 * 1024 * 1024)
                    return "Medium · 1–100 MiB";
                if(item.bytes < 1024 * 1024 * 1024)
                    return "Large · 100 MiB–1 GiB";
                return "Very Large · 1 GiB or More";
            }
            if(mode == "Modified Date" || mode == "Recent Date")
            {
                string attribute = mode == "Recent Date" ? "majoris::recent" : "time::modified";
                if(!item.info.has_attribute(attribute))
                    return "Unknown Date";
                var now = new DateTime.now_local();
                var today = new DateTime.local(now.get_year(), now.get_month(), now.get_day_of_month(), 0, 0, 0);
                int64 timestamp = (int64)item.info.get_attribute_uint64(attribute);
                if(timestamp >= today.add_days(1).to_unix())
                    return "Future";
                if(timestamp >= today.to_unix())
                    return "Today";
                if(timestamp >= today.add_days(-1).to_unix())
                    return "Yesterday";
                if(timestamp >= today.add_days(-7).to_unix())
                    return "Previous 7 Days";
                if(timestamp >= today.add_days(-30).to_unix())
                    return "Previous 30 Days";
                return "Older";
            }
            if(mode == "Tags")
            {
                var tags = new Gee.ArrayList<string>();
                foreach (var tag in metadata.tags_for(item.file)) tags.add(tag.name);
                tags.sort((a, b) => Paths.natural_compare(a, b));
                return tags.size == 0 ? "Untagged" : string.joinv(", ", tags.to_array());
            }
            return "";
        }
        public static int compare(FileItem first, FileItem second, string mode, MetadataStore metadata)
        {
            var a = label(first, mode, metadata);
            var b = label(second, mode, metadata);
            if(mode == "Modified Date" || mode == "Recent Date")
            {
                string[] order = {
                    "Future", "Today", "Yesterday", "Previous 7 Days", "Previous 30 Days", "Older", "Unknown Date"
                };
                return rank(a, order) - rank(b, order);
            }
            if(mode == "Size")
            {
                string[] order = {
                    "Folders", "Empty", "Small · Under 1 MiB", "Medium · 1–100 MiB", "Large · 100 MiB–1 GiB", "Very Large · 1 GiB or More"
                };
                return rank(a, order) - rank(b, order);
            }
            return Paths.natural_compare(a, b);
        }
        static int rank(string label, string[] order)
        {
            for(int i = 0; i < order.length; i++)
                if(label == order[i])
                    return i;
            return order.length;
        }
    }
}
