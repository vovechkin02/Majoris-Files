namespace MajorisFiles {
    public interface ColumnProvider : Object {
        public abstract string title {
            owned get;
        }
        public abstract string text(FileItem item, MetadataStore metadata);
        public abstract int compare(FileItem first, FileItem second, MetadataStore metadata);
    }
}
