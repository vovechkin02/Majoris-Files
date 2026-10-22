namespace MajorisFiles {
    public class GridRow : Object {
        public uint start;
        public uint count;
        public bool heading;
        public string label = "";
        public GridRow(uint start, uint count, bool heading) { this.start=start; this.count=count; this.heading=heading; }
    }
    // Stores section boundaries, never one object per file. GTK requests only
    // the visible rows; each nested grid has at most sixteen live cells.
    public class GridRows : Object, ListModel {
        Gtk.SortListModel source;
        Gee.ArrayList<uint> starts = new Gee.ArrayList<uint>();
        Gee.ArrayList<uint> ends = new Gee.ArrayList<uint>();
        Gee.ArrayList<string> labels = new Gee.ArrayList<string>();
        MetadataStore? metadata;
        public string mode = "None";
        uint length;
        uint previous_columns = 4;
        public uint columns = 4;
        ulong items_handler;
        ulong sections_handler;
        public GridRows(Gtk.SortListModel source, MetadataStore? metadata = null) {
            this.source=source;
            this.metadata=metadata;
            items_handler=source.items_changed.connect(refresh);
            sections_handler=source.sections_changed.connect(refresh);
            refresh();
        }
        public void resize(uint value) { value=value.clamp(1,16); if(columns!=value){columns=value; refresh();} }
        public uint row_for(uint position){uint row=0;for(int i=0;i<starts.size;i++){if(position<ends[i])return row+1+(position-starts[i])/columns;row+=1+(ends[i]-starts[i]+columns-1)/columns;}return row;}
        public Type get_item_type(){return typeof(GridRow);}
        public uint get_n_items(){return length;}
        public Object? get_item(uint position){
            if(position>=length)return null;
            for(int i=0;i<starts.size;i++){
                uint rows=1+(ends[i]-starts[i]+columns-1)/columns;
                if(position<rows){
                    if(position==0){var row=new GridRow(starts[i],0,true);row.label=labels[i];return row;}
                    uint start=starts[i]+(position-1)*columns;
                    return new GridRow(start,uint.min(columns,ends[i]-start),false);
                }
                position-=rows;
            }
            return null;
        }
        public void refresh(){
            var previous_starts=starts; var previous_ends=ends; uint previous=length;
            var previous_labels=labels;labels=new Gee.ArrayList<string>();
            starts=new Gee.ArrayList<uint>(); ends=new Gee.ArrayList<uint>(); length=0;
            uint cursor=0;
            while(cursor<source.get_n_items()){
                uint start,end; source.get_section(cursor,out start,out end);
                end=uint.min(end,source.get_n_items()); if(end<=cursor)break;
                var item=source.get_item(cursor) as FileItem;
                string label="";
                if(item!=null){
                    if(metadata!=null)label=FileGroups.label(item,mode,metadata);
                    else label=item.file.get_uri();
                }
                labels.add(label);
                starts.add(cursor);ends.add(end);length+=1+(end-cursor+columns-1)/columns;cursor=end;
            }
            // Keep unaffected leading sections alive during incremental updates.
            uint prefix=0;
            for(int i=0;i<int.min(starts.size,previous_starts.size);i++){
                if(previous_columns!=columns)break;
                if(starts[i]!=previous_starts[i]||ends[i]!=previous_ends[i])break;
                if(labels[i]!=previous_labels[i])break;
                prefix+=1+(ends[i]-starts[i]+columns-1)/columns;
            }
            previous_columns=columns;
            if(previous!=prefix||length!=prefix)items_changed(prefix,previous-prefix,length-prefix);
        }
        public void detach(){if(items_handler!=0){source.disconnect(items_handler);source.disconnect(sections_handler);items_handler=0;}}
        ~GridRows(){detach();}
    }
    public class GridSlice : Object, ListModel, Gtk.SelectionModel {
        public Gtk.SelectionModel source;
        public uint offset;
        uint count;
        Gtk.SliceListModel slice;
        ulong handler;
        ulong items_handler;
        public GridSlice(Gtk.SelectionModel source,uint offset,uint count){
            this.source=source;this.offset=offset;this.count=count;
            slice=new Gtk.SliceListModel(source,offset,count);
            items_handler=slice.items_changed.connect((p,r,a)=>items_changed(p,r,a));
            handler=source.selection_changed.connect((p,n)=>{
                uint a=uint.max(p,offset),b=uint.min(p+n,offset+count);
                if(b>a)selection_changed(a-offset,b-a);
            });
        }
        public Type get_item_type(){return source.get_item_type();}
        public uint get_n_items(){return slice.get_n_items();}
        public Object? get_item(uint p){return slice.get_item(p);}
        public bool is_selected(uint p){return p<get_n_items()&&source.is_selected(offset+p);}
        public Gtk.Bitset get_selection_in_range(uint p,uint n){var result=new Gtk.Bitset.empty();for(uint i=p;i<uint.min(p+n,get_n_items());i++)if(is_selected(i))result.add(i);return result;}
        public bool select_item(uint p,bool rest){return p<get_n_items()&&source.select_item(offset+p,rest);}
        public bool unselect_item(uint p){return p<get_n_items()&&source.unselect_item(offset+p);}
        public bool select_range(uint p,uint n,bool rest){return p<get_n_items()&&source.select_range(offset+p,uint.min(n,get_n_items()-p),rest);}
        public bool unselect_range(uint p,uint n){return p<get_n_items()&&source.unselect_range(offset+p,uint.min(n,get_n_items()-p));}
        public bool select_all(){return source.select_all();}
        public bool unselect_all(){return source.unselect_all();}
        public bool set_selection(Gtk.Bitset selected,Gtk.Bitset mask){
            var global_selected=new Gtk.Bitset.empty();var global_mask=new Gtk.Bitset.empty();
            for(uint i=0;i<get_n_items();i++){if(mask.contains(i))global_mask.add(offset+i);if(selected.contains(i))global_selected.add(offset+i);}
            return source.set_selection(global_selected,global_mask);
        }
        public void detach(){if(handler!=0){source.disconnect(handler);slice.disconnect(items_handler);handler=0;}}
        ~GridSlice(){detach();}
    }
}
