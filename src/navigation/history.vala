namespace MajorisFiles {
    public class History : Object {
        Gee.ArrayList<File> entries = new Gee.ArrayList<File>();
        int index = -1;
        public bool can_back {
            get {
                return index > 0;
            }
        }
        public bool can_forward {
            get {
                return index + 1 < entries.size;
            }
        }
        public void visit(File file)
        {
            if (index >= 0 && entries[index].equal(file))
                return;
            while (entries.size > index + 1)
                entries.remove_at(entries.size - 1);
            entries.add(file);
            index++;
        }
        public File? back()
        {
            return can_back ? entries[--index] : null;
        }
        public File? forward()
        {
            return can_forward ? entries[++index] : null;
        }
    }
}
