using MajorisFiles;

async void pause_layout() {
    Timeout.add(500, () => { pause_layout.callback(); return Source.REMOVE; });
    yield;
}
Gtk.Widget? find_component(Gtk.Widget widget, string name) {
    if(widget.has_css_class(name)) return widget;
    for(var c=widget.get_first_child();c!=null;c=c.get_next_sibling()) {
        var found=find_component(c,name);if(found!=null)return found;
    }
    return null;
}
void record_tree(Gtk.Widget widget, Json.Builder json) {
    if(!widget.get_mapped())return;
    Gtk.Allocation allocation;widget.get_allocation(out allocation);
    Graphene.Rect bounds;widget.compute_bounds((Gtk.Widget)widget.get_root(),out bounds);
    json.begin_object();
    json.set_member_name("x");json.add_int_value(allocation.x);
    json.set_member_name("y");json.add_int_value(allocation.y);
    json.set_member_name("absolute_x");json.add_double_value(bounds.origin.x);
    json.set_member_name("absolute_y");json.add_double_value(bounds.origin.y);
    json.set_member_name("bounds_width");json.add_double_value(bounds.size.width);
    json.set_member_name("bounds_height");json.add_double_value(bounds.size.height);
    json.set_member_name("state_flags");json.add_int_value((int)widget.get_state_flags());
    json.set_member_name("focus_visible");json.add_boolean_value((widget.get_state_flags() & Gtk.StateFlags.FOCUS_VISIBLE)!=0);
    json.set_member_name("selected");json.add_boolean_value((widget.get_state_flags() & Gtk.StateFlags.SELECTED)!=0);
    json.set_member_name("has_focus");json.add_boolean_value(widget.has_focus);
    json.set_member_name("overflow");json.add_string_value(widget.overflow.to_string());
    json.set_member_name("node");json.add_string_value(widget.get_css_name());
    json.set_member_name("classes");json.begin_array();foreach(var name in widget.get_css_classes())json.add_string_value(name);json.end_array();
    json.set_member_name("allocated_width");json.add_int_value(widget.get_allocated_width());
    json.set_member_name("allocated_height");json.add_int_value(widget.get_allocated_height());
    json.set_member_name("width");json.add_int_value(widget.get_width());
    json.set_member_name("height");json.add_int_value(widget.get_height());
    json.set_member_name("baseline");json.add_int_value(widget.get_allocated_baseline());
    if(widget is Gtk.Image){json.set_member_name("icon_size");json.add_int_value(((Gtk.Image)widget).pixel_size);}
    if(widget is Gtk.Label) {
        var label=(Gtk.Label)widget;Pango.Rectangle ink,logical;
        int layout_x,layout_y;label.get_layout_offsets(out layout_x,out layout_y);
        label.get_layout().get_pixel_extents(out ink,out logical);
        json.set_member_name("layout_x");json.add_int_value(layout_x);
        json.set_member_name("layout_y");json.add_int_value(layout_y);
        json.set_member_name("pango_baseline");json.add_double_value((double)label.get_layout().get_baseline()/Pango.SCALE);
        json.set_member_name("rendered_baseline");json.add_double_value(layout_y+(double)label.get_layout().get_baseline()/Pango.SCALE);
        json.set_member_name("ink_x");json.add_int_value(ink.x);
        json.set_member_name("ink_width");json.add_int_value(ink.width);
        json.set_member_name("logical_width");json.add_int_value(logical.width);
        var context=label.get_layout().get_context();
        var font=context.load_font(context.get_font_description());
        json.set_member_name("resolved_font");json.add_string_value(font==null?"unavailable":font.describe().to_string());
        json.set_member_name("font_resolution");json.add_double_value(Pango.cairo_context_get_resolution(context));
        json.set_member_name("margin_top");json.add_int_value(label.margin_top);
        json.set_member_name("margin_bottom");json.add_int_value(label.margin_bottom);
        json.set_member_name("height_request");json.add_int_value(label.height_request);
        json.set_member_name("text");json.add_string_value(label.label);
        json.set_member_name("ink_height");json.add_int_value(ink.height);
        json.set_member_name("logical_height");json.add_int_value(logical.height);
        json.set_member_name("ink_y");json.add_int_value(ink.y);
        json.set_member_name("logical_y");json.add_int_value(logical.y);
        json.set_member_name("font");json.add_string_value(label.get_layout().get_context().get_font_description().to_string());
    }
    json.set_member_name("children");json.begin_array();
    for(var c=widget.get_first_child();c!=null;c=c.get_next_sibling())record_tree(c,json);
    json.end_array();json.end_object();
}
void reset_scroll(Gtk.Widget widget) {
    if(widget is Gtk.ScrolledWindow) ((Gtk.ScrolledWindow)widget).vadjustment.value=0;
    for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling())reset_scroll(child);
}
async void capture(Gtk.Window window,string output,string name) throws Error {
    reset_scroll(window);
    Gsk.RenderNode? node=null;
    for(int attempt=0;attempt<6 && node==null;attempt++) {
        yield pause_layout();
        var paintable=new Gtk.WidgetPaintable(window);var snapshot=new Gtk.Snapshot();
        paintable.snapshot(snapshot,window.get_width(),window.get_height());node=snapshot.to_node();
    }
    assert(node!=null);
    var renderer=Gsk.Renderer.for_surface(window.get_surface());var texture=renderer.render_texture(node,null);
    assert(texture.save_to_png(Path.build_filename(output,name+".png")));renderer.unrealize();
    var json=new Json.Builder();record_tree(window,json);var generator=new Json.Generator();generator.set_root(json.get_root());generator.pretty=true;
    FileUtils.set_contents(Path.build_filename(output,name+".json"),generator.to_data(null));
}
