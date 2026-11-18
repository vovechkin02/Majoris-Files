using MajorisFiles;

string? evidence;
bool open_details(Gtk.Widget widget) {
    if (widget is Adw.ActionRow && ((Adw.ActionRow)widget).title == "Details") { ((Adw.ActionRow)widget).activated(); return true; }
    for (var child = widget.get_first_child(); child != null; child = child.get_next_sibling())
        if (open_details(child)) return true;
    return false;
}
Gtk.GridView? find_grid(Gtk.Widget widget) {
    if (widget is Gtk.GridView) return (Gtk.GridView)widget;
    for (var child = widget.get_first_child(); child != null; child = child.get_next_sibling()) {
        var found = find_grid(child); if (found != null) return found;
    }
    return null;
}
int tile_count(Gtk.Widget widget) {
    int count = (widget is GridFileItem) ? 1 : 0;
    for (var child = widget.get_first_child(); child != null; child = child.get_next_sibling()) count += tile_count(child);
    return count;
}
async void short_tick() {
    Timeout.add(20, () => { short_tick.callback(); return Source.REMOVE; }); yield;
}
async void stress(File fixtures, File root, MetadataStore settings) throws Error {
    if (Environment.get_variable("MAJORIS_IMAGEKIT_STRESS") != "1") return;
    settings.set_state("thumbnail-policy", "Local");
    var directory = root.get_child("mixed-images"); yield directory.make_directory_async();
    var bytes = yield fixtures.get_child("rgb8.png").load_bytes_async(null, null);
    for (int i = 0; i < 1000; i++) {
        yield directory.get_child("image-%04d.png".printf(i)).replace_contents_async(bytes.get_data(), null, false, FileCreateFlags.PRIVATE, null, null);
        yield directory.get_child("document-%04d.txt".printf(i)).replace_contents_async("fixture".data, null, false, FileCreateFlags.PRIVATE, null, null);
    }
    var app = new Adw.Application("com.majoris.files.imagekitstress", ApplicationFlags.NON_UNIQUE); app.register(null);
    var places = new Places(settings); var operations = new OperationManager(settings);
    var first = new FilesWindow(app, settings, places, operations, directory);
    var second = new FilesWindow(app, settings, places, operations, directory);
    first.present(); second.present();
    while (first.current.directory.loading || second.current.directory.loading) yield short_tick();
    assert(first.current.directory.items.get_n_items() == 2000);
    first.new_tab(fixtures);
    uint heartbeats = 0; int peak_tiles = 0;
    uint timer = Timeout.add(1, () => { heartbeats++; return Source.CONTINUE; });
    int64 started = get_monotonic_time();
    for (int i = 0; i < 64; i++) {
        first.tabs.selected_page = first.tabs.get_nth_page(i % 2);
        var grid = find_grid(second.current.file_surface);
        if (grid != null) grid.scroll_to((uint)((i * 137) % 2000), Gtk.ListScrollFlags.NONE, null);
        peak_tiles = int.max(peak_tiles, tile_count(second.current.file_surface));
        second.current.preview.show_item.begin(yield item_for(fixtures.get_child(i % 2 == 0 ? "rgb8.png" : "rgb16.png")));
        yield short_tick();
    }
    second.current.preview.cancel();
    Source.remove(timer);
    assert(heartbeats > 0 && peak_tiles < 1000); // Real list virtualization, not one viewer per entry.
    stdout.printf("Mixed-directory stress: 2000 entries (1000 images), 64 rapid scroll/preview/tab switches, two windows; %.3f s; %u heartbeats; peak %d instantiated Grid tiles\n", (get_monotonic_time() - started) / 1000000.0, heartbeats, peak_tiles);
    first.current.cancel(); second.current.cancel(); first.destroy(); second.destroy();
}
async void visual_surfaces(File fixtures, MetadataStore settings) throws Error {
    if (evidence == null) return;
    settings.set_state("thumbnail-policy", "Local");
    var visual_directory = File.new_for_path(DirUtils.make_tmp("majoris-imagekit-visual-XXXXXX"));
    foreach (var name in new string[] {"rgb8.png", "rgb16.png", "multipage.tiff", "multipart.exr"})
        yield fixtures.get_child(name).copy_async(visual_directory.get_child(name), FileCopyFlags.NONE, Priority.DEFAULT, null, null);
    var jpeg_options = new ImageKit.ExportOptions(); jpeg_options.format = "jpeg"; jpeg_options.bit_depth = 8;
    yield new ImageKit.EncoderRegistry().encode(new ImageKit.ImageSource(fixtures.get_child("rgb8.png")), visual_directory.get_child("photo.jpg"), jpeg_options);
    var raw_path = Environment.get_variable("MAJORIS_IMAGEKIT_RAW");
    if (raw_path != null) {
        var raw = File.new_for_path(raw_path);
        yield raw.copy_async(visual_directory.get_child(raw.get_basename()), FileCopyFlags.NONE, Priority.DEFAULT, null, null);
    }
    var app = new Adw.Application("com.majoris.files.imagekitvisual", ApplicationFlags.NON_UNIQUE);
    app.register(null);
    var places = new Places(settings);
    var files = new FilesWindow(app, settings, places, new OperationManager(settings), visual_directory);
    files.set_default_size(1040, 820); files.present();
    yield pause_layout();
    var browser = files.current;
    for (uint i = 0; i < browser.active_selection.get_n_items(); i++) {
        var item = browser.active_selection.get_item(i) as FileItem;
        if (item != null && item.name == "rgb16.png") browser.active_selection.select_item(i, true);
    }
    yield capture(files, evidence, "grid");
    browser.set_group("Type"); yield capture(files, evidence, "grouped-grid");
    browser.set_group("None"); browser.set_view("List"); yield capture(files, evidence, "list");
    browser.set_view("Gallery"); browser.select_file(visual_directory.get_child("rgb16.png")); yield capture(files, evidence, "gallery");
    browser.set_view("Grid"); browser.preview.visible = true;
    var selected = yield item_for(visual_directory.get_child("rgb16.png"));
    browser.select_file(selected.file);
    yield browser.preview.show_item(selected);
    yield capture(files, evidence, "preview-pane");
    var items = new Gee.ArrayList<FileItem>(); items.add(selected);
    var properties = new PropertiesDialog(files, items, settings); properties.present(files);
    yield capture(files, evidence, "properties");
    assert(open_details(properties)); yield capture(files, evidence, "image-metadata"); properties.close();
    var conflict = new Adw.AlertDialog("Image comparison", null);
    ConflictThumbnails.attach(conflict, fixtures.get_child("rgb8.png"), fixtures.get_child("rgb16.png"), settings);
    conflict.add_response("close", "Close"); conflict.present(files);
    yield capture(files, evidence, "conflict"); conflict.close();
    var quick = new QuickPreviewWindow(); quick.pane.configure(settings); quick.present();
    yield quick.pane.show_item(selected); yield capture(quick, evidence, "quick-preview");
    quick.pane.cancel(); quick.destroy();
    foreach (bool save in new bool[] {false, true}) {
        var options = new ChooserOptions(save, new VariantBuilder(VariantType.VARDICT).end()); options.initial = visual_directory;
        var chooser = new ChooserWindow(options, settings, places); chooser.present();
        yield capture(chooser, evidence, save ? "save-chooser" : "open-chooser"); chooser.cancel_request();
    }
    browser.cancel(); files.destroy();
}
async FileItem item_for(File file) throws Error {
    var info = yield file.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, null);
    return new FileItem(file, info);
}
async void exercise(File fixtures, File root) throws Error {
    var token = new Cancellable();
    var dispatcher = new FileThumbnailService();
    var integration = ImageKitIntegration.get_default();
    assert(ImageKitIntegration.thumbnail_edge(128, 2) == 256);
    assert(ImageKitIntegration.thumbnail_edge(1000, 16) == 1024);
    assert(ImageKitIntegration.thumbnail_edge(1, 1) == 32);
    var image = root.get_child("editable.png");
    yield fixtures.get_child("rgb8.png").copy_async(image, FileCopyFlags.NONE, Priority.DEFAULT, token, null);
    var item = yield item_for(image);
    var original = yield integration.metadata(item, token);
    var preview = new ImageKitPreview();
    var window = new Gtk.Window();
    window.set_default_size(500, 400); window.child = preview; window.present();
    yield preview.load(item, token);
    if (evidence != null) yield capture(window, evidence, "image-preview");
    assert(preview.image_view.document != null);
    assert(preview.image_view.state == ImageKit.ViewState.READY);
    assert(preview.image_view.scroll_zoom_mode == ImageKit.ScrollZoomMode.CONTROL);
    preview.image_view.actual_size();
    preview.image_view.zoom_in(); preview.image_view.zoom_out();
    preview.image_view.rotate_clockwise(); preview.image_view.fit_to_view();
    var thumb = yield dispatcher.texture(item, token, 128, 2);
    assert(thumb != null && thumb.width <= 256 && thumb.height <= 256);
    var cached = yield dispatcher.texture(item, token, 128, 2);
    assert(cached.width == thumb.width && cached.height == thumb.height);
    assert(!File.new_for_path(Path.build_filename(Environment.get_user_cache_dir(), "thumbnails", "normal")).query_exists());
    var cache = File.new_for_path(Path.build_filename(Environment.get_user_cache_dir(), "majoris-image", "thumbnails-v2"));
    var entries = yield cache.enumerate_children_async("standard::name", 0, Priority.DEFAULT, token);
    while (true) {
        var batch = yield entries.next_files_async(16, Priority.DEFAULT, token);
        if (batch == null) break;
        foreach (var entry in batch) if (entry.get_name().has_suffix(".png"))
            yield cache.get_child(entry.get_name()).replace_contents_async("broken cache".data, null, false, FileCreateFlags.PRIVATE, token, null);
    }
    yield entries.close_async(Priority.DEFAULT, token);
    assert((yield dispatcher.texture(item, token)) != null);
    // One cancelled consumer cannot cancel another consumer of the shared service.
    var cancelled = new Cancellable(); cancelled.cancel();
    bool rejected = false;
    try { yield dispatcher.texture(item, cancelled); } catch (IOError.CANCELLED e) { rejected = true; }
    assert(rejected);
    assert((yield dispatcher.texture(item, token)) != null);
    var settings = new MetadataStore(root.get_child("settings.db").get_path());
    settings.set_state("thumbnail-policy", "Never");
    assert((yield new FileThumbnailService(settings).texture(item, token)) == null);
    // Remote sources must never reach ImageKit without Files' policy/staging handoff.
    var remote_info = item.info.dup();
    var remote = new FileItem(File.new_for_uri("sftp://example.invalid/no-network.png"), remote_info);
    rejected = false;
    try { ImageKitIntegration.source(remote); } catch (IOError.NOT_SUPPORTED e) { rejected = true; }
    assert(rejected);
    foreach (var name in new string[] {"rgb16.png", "multipage.tiff", "multipart.exr"}) {
        var selection = yield item_for(fixtures.get_child(name));
        yield preview.load(selection, token);
        if (evidence != null) yield capture(window, evidence, name);
        assert(preview.image_view.document != null);
        var metadata = yield integration.metadata(selection, token);
        assert(metadata.has_key("Dimensions") && metadata.has_key("Source Bit Depth"));
        if (name == "rgb16.png") assert(metadata["Source Bit Depth"] == "16");
        if (name == "multipart.exr") {
            assert(preview.image_view.hdr_source);
            assert(preview.image_view.presentation_status != ImageKit.PresentationStatus.NATIVE_HDR);
        }
        if (preview.image_view.page_count > 1) {
            yield preview.image_view.set_page(1, token);
            assert(preview.image_view.current_page == 1);
        }
    }
    var gif = root.get_child("animated.gif");
    yield gif.replace_contents_async(Base64.decode("R0lGODlhAQABAIAAAAAAAP///yH5BAAKAAAALAAAAAABAAEAAAICRAEAIfkEAAoAAAAsAAAAAAEAAQAAAgJMAQA7"), null, false, FileCreateFlags.PRIVATE, token, null);
    yield preview.load(yield item_for(gif), token);
    assert(preview.image_view.animated);
    if (evidence != null) yield capture(window, evidence, "animation");
    preview.image_view.pause(); yield preview.image_view.seek_frame(1, token);
    assert(preview.image_view.current_frame == 1);
    preview.image_view.play(); preview.image_view.pause();
    var raw_path = Environment.get_variable("MAJORIS_IMAGEKIT_RAW");
    if (raw_path != null) {
        var raw = yield item_for(File.new_for_path(raw_path));
        var original_raw = yield SplitService.checksum(raw.file, ChecksumType.SHA256, token);
        assert((yield dispatcher.texture(raw, token)) != null);
        yield preview.load(raw, token);
        assert((yield integration.metadata(raw, token))["RAW Source"] == _("Yes"));
        if (evidence != null) yield capture(window, evidence, "raw-preview");
        assert((yield SplitService.checksum(raw.file, ChecksumType.SHA256, token)) == original_raw);
    }
    // New selections cancel obsolete ImageKit loads without publishing old documents.
    for (int i = 0; i < 12; i++) {
        var stop = new Cancellable();
        preview.image_view.load_file.begin(image, ImageKitIntegration.preview_options(), stop, (obj, result) => {
            try { preview.image_view.load_file.end(result); } catch (Error e) { assert(e is IOError.CANCELLED); }
        });
        stop.cancel();
        yield preview.image_view.load_file(fixtures.get_child("rgb16.png"));
        assert(preview.image_view.document.source_bit_depth == 16);
    }
    var bad = root.get_child("corrupt.png");
    yield bad.replace_contents_async("invalid image".data, null, false, FileCreateFlags.PRIVATE, token, null);
    var bad_item = yield item_for(bad);
    rejected = false;
    try { yield preview.load(bad_item, token); } catch (Error e) { rejected = true; }
    assert(rejected);
    rejected = false;
    try { yield dispatcher.texture(bad_item, token); } catch (Error e) { rejected = true; }
    assert(rejected);
    // PNG persistent rotation uses ImageKit export, then Files replacement and Undo.
    var operations = new OperationManager(settings);
    yield ImageRotation.rotate(item, true, operations);
    var rotated = yield integration.metadata(yield item_for(image), token);
    var original_dimensions = original["Dimensions"].split(" × ");
    assert(rotated["Dimensions"] == original_dimensions[1] + " × " + original_dimensions[0]);
    yield ImageRotation.rotate(yield item_for(image), false, operations);
    assert((yield integration.metadata(yield item_for(image), token))["Dimensions"] == original["Dimensions"]);
    // Changed/deleted inputs must be revalidated by the shared service.
    yield image.replace_contents_async("truncated".data, null, false, FileCreateFlags.PRIVATE, token, null);
    rejected = false;
    try { yield dispatcher.texture(item, token); } catch (Error e) { rejected = true; }
    assert(rejected);
    yield image.delete_async(Priority.DEFAULT, token);
    rejected = false;
    try { yield integration.thumbnail(item, 128, token); } catch (Error e) { rejected = true; }
    assert(rejected);
    yield visual_surfaces(fixtures, settings);
    yield stress(fixtures, root, settings);
    token.cancel(); window.destroy();
}
int main(string[] args) {
    try {
        var root = File.new_for_path(DirUtils.make_tmp("majoris-imagekit-test-XXXXXX"));
        Environment.set_variable("XDG_CACHE_HOME", root.get_child("cache").get_path(), true);
        Environment.set_variable("XDG_DATA_HOME", root.get_child("data").get_path(), true);
        Environment.set_variable("XDG_CONFIG_HOME", root.get_child("config").get_path(), true);
        Adw.init(); ImageKit.ImageView.register_type();
        evidence = Environment.get_variable("MAJORIS_IMAGEKIT_EVIDENCE");
        if (evidence != null) DirUtils.create_with_parents(evidence, 0700);
        if (Environment.get_variable("MAJORIS_VISUAL_DARK") == "1") Adw.StyleManager.get_default().color_scheme = Adw.ColorScheme.FORCE_DARK;
        var loop = new MainLoop(); int status = 0;
        exercise.begin(File.new_for_path(args[1]), root, (obj, result) => {
            try { exercise.end(result); } catch (Error e) { stderr.printf("%s\n", e.message); status = 1; }
            loop.quit();
        });
        loop.run();
        return status;
    } catch (Error e) { stderr.printf("%s\n", e.message); return 1; }
}
