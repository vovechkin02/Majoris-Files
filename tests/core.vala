using MajorisFiles;
int main(string[] args)
{
    Test.init(ref args);
    Test.add_func("/accounts/empty-description", () => {
        var users = AccountDirectory.parse("service:x:1001:1001::/nonexistent:/usr/sbin/nologin", true);
        assert(users.size == 1 && users[0].label == "service · 1001");
    });
    Test.add_func("/paths/optional-remote-attributes",()=>{
        var info=new FileInfo();info.set_name(".remote-hidden");assert(Paths.is_hidden(info)&&!Paths.is_symlink(info));
        info.set_attribute_boolean("standard::is-hidden",false);assert(!Paths.is_hidden(info));
        info.set_file_type(FileType.SYMBOLIC_LINK);assert(Paths.is_symlink(info));
    });
    Test.add_func("/paths/validation", () => { assert(Paths.valid_name("report.txt"));
                                               assert(!Paths.valid_name("../escape"));
                                               assert(!Paths.valid_name(".."));
                                               assert(!Paths.valid_name(""));
                                               assert(Paths.max_file_size("vfat") == 4294967295);
        });
    Test.add_func("/paths/natural", () => { assert(Paths.natural_compare("file2", "file10") < 0);
        });
    Test.add_func("/history/branch", () => { var h = new History();
                                             var a = File.new_for_path("/a");
                                             var b = File.new_for_path("/b");
                                             h.visit(a);
                                             h.visit(b);
                                             assert(h.back().equal(a));
                                             h.visit(File.new_for_path("/c"));
                                             assert(!h.can_forward);
        });
    Test.add_func("/chooser/options", () => { try { var b = new VariantBuilder(VariantType.VARDICT);
                                                    b.add("{sv}", "multiple", new Variant.boolean(true));
                                                    b.add("{sv}", "current_name", new Variant.string("Document.txt"));
                                                    var options = new ChooserOptions(false, b.end());
                                                    assert(options.multiple);
                                                    assert(options.current_name == "Document.txt");
                                              }
                                              catch (Error e) { error("%s", e.message);
                                              }
        });
    Test.add_func("/chooser/malformed", () => { var b = new VariantBuilder(VariantType.VARDICT);
                                                b.add("{sv}", "multiple", new Variant.string("yes"));
                                                bool rejected = false;
                                                try { new ChooserOptions(false, b.end());
                                                }
                                                catch (Error e) { rejected = true;
                                                }
                                                assert(rejected);
        });
    Test.add_func("/chooser/filter-extension", () => { try { var rules = new VariantBuilder(new VariantType("a(us)"));
                                                             rules.add("(us)", 0u, "*.txt");
                                                             var filter = new ChooserFilter(new Variant("(s@a(us))", "Text", rules.end()));
                                                             assert(filter.filename("Document") == "Document.txt");
                                                             assert(filter.filename("Document.txt") == "Document.txt");
                                                             assert(filter.filename("Document.md") == "Document.md");
                                                             var info = new FileInfo();
                                                             info.set_name("folder");
                                                             info.set_file_type(FileType.DIRECTORY);
                                                             assert(filter.matches(new FileItem(File.new_for_path("/folder"), info)));
                                                       }
                                                       catch (Error e) { error("%s", e.message);
                                                       }
        });
    Test.add_func("/chooser/response", () => { try { var result = ChooserOptions.response({"file:///tmp/report.txt"});
                                                     assert(result.lookup_value("uris", new VariantType("as")).n_children() == 1);
                                                     bool rejected = false;
                                                     try { ChooserOptions.response({"smb://server/secret"});
                                                     }
                                                     catch (Error e) { rejected = true;
                                                     }
                                                     assert(rejected);
                                               }
                                               catch (Error e) { error("%s", e.message);
                                               }
        });
    Test.add_func("/metadata/persistence", () => { try { var dir = DirUtils.make_tmp("majoris-tests-XXXXXX");
                                                         var path = Path.build_filename(dir, "metadata.db");
                                                         var file = File.new_for_path("/example");
                                                         { var store = new MetadataStore(path);
                                                           store.set_favorite(file, true);
                                                           store.set_tags(file, "Work,Finance");
                                                         }
                                                         var store = new MetadataStore(path);
                                                         assert(store.favorite(file));
                                                         assert(store.tags(file) == "Work,Finance");
                                                         store.relocate(file, File.new_for_path("/renamed"));
                                                         assert(store.favorite(File.new_for_path("/renamed")));
                                                   }
                                                   catch (Error e) { error("%s", e.message);
                                                   }
        });
    Test.add_func("/split/sizing", () => { try { assert(Paths.split_size(10, 3) == 4);
                                                 assert(Paths.part_name("movie.mkv", 1000) == "movie.mkv.part1000");
                                           }
                                           catch (Error e) { error("%s", e.message);
                                           }
        });
    Test.add_func("/split/malformed-manifest", () => { foreach(var content in new string[] {"{}", "{\"format\":3}", "{\"format\":\"majoris-split-file\",\"version\":1,\"original_filename\":\"../escape\",\"original_size\":1,\"sha256\":\"abc\",\"parts\":[]}"})
                                                       {
                                                           bool rejected = false;
                                                           try { var parser = new Json.Parser();
                                                                 parser.load_from_data(content);
                                                                 SplitService.validate_manifest(parser.get_root().get_object());
                                                           }
                                                           catch(Error e) { rejected = true;
                                                           }
                                                           assert(rejected);
                                                       }
        });
    Test.add_func("/chooser/private-state", () => {
        try {
            var temp = DirUtils.make_tmp("majoris-state-XXXXXX");
            var path = Path.build_filename(temp, "metadata.db");
            var metadata = new MetadataStore(path);
            var first = new ChooserState(metadata, "org.example.First");
            first.set("open-location", "file:///tmp/first");
            first.set("save-location", "file:///tmp/save");
            first.set("view", "List");
            first.set("sidebar-width", "99999");
            assert(first.dimension("sidebar-width", 180, 120, 420) == 420);
            first.set("sidebar-width", "invalid");
            assert(first.dimension("sidebar-width", 180, 120, 420) == 180);
            var second = new ChooserState(metadata, "org.example.Second");
            assert(second.get("view", "Grid") == "Grid");
            var anonymous = new ChooserState(metadata, "");
            anonymous.set("view", "List");
            assert(anonymous.get("view", "Grid") == "Grid");
            var reopened = new ChooserState(new MetadataStore(path), "org.example.First");
            assert(reopened.get("view") == "List");
            var options = new ChooserOptions(false, new VariantBuilder(VariantType.VARDICT).end());
            reopened.apply(options);
            assert(options.initial.equal(File.new_for_uri("file:///tmp/first")));
            var save = new ChooserOptions(true, new VariantBuilder(VariantType.VARDICT).end());
            reopened.apply(save);
            assert(save.initial.equal(File.new_for_uri("file:///tmp/save")));
            var supplied = new VariantBuilder(VariantType.VARDICT);
            supplied.add("{sv}", "current_folder", new Variant.bytestring(Environment.get_home_dir()));
            var explicit_options = new ChooserOptions(false, supplied.end());
            reopened.apply(explicit_options);
            assert(explicit_options.initial.equal(File.new_for_path(Environment.get_home_dir())));
        }
        catch(Error e) { error("%s", e.message);
        }
    });
    Test.add_func("/clipboard/file-formats", () => {
        try {
            var copied = FileClipboard.parse("cut\nfile:///tmp/a%20b\nfile:///tmp/a%20b\n", true);
            assert(copied.cut && copied.files.size == 1);
            assert(copied.files[0].equal(File.new_for_path("/tmp/a b")));
            var uris = FileClipboard.parse("# comment\r\nfile:///tmp/one\r\nsmb://server/share/two\r\n", false);
            assert(!uris.cut && uris.files.size == 2);
            bool rejected = false;
            try { FileClipboard.parse("delete\nfile:///tmp/one", true);
            }
            catch(Error e) { rejected = true;
            }
            assert(rejected);
            rejected = false;
            try { FileClipboard.parse("/tmp/unqualified", false);
            }
            catch(Error e) { rejected = true;
            }
            assert(rejected);
        }
        catch(Error e) { error("%s", e.message);
        }
    });
    Test.add_func("/search/predicates-and-persistence", () => {
        try {
            var temp = DirUtils.make_tmp("majoris-search-XXXXXX");
            var metadata = new MetadataStore(Path.build_filename(temp, "meta.db"));
            var file = File.new_for_path("/tmp/Report.pdf");
            var info = new FileInfo();
            info.set_name("Report.pdf");
            info.set_display_name("Report.pdf");
            info.set_file_type(FileType.REGULAR);
            info.set_size(4096);
            info.set_content_type("application/pdf");
            info.set_attribute_uint64("time::modified", 1000);
            info.set_attribute_string("owner::user", "alice");
            var item = new FileItem(file, info);
            metadata.set_tags(file, "Work, Finance");
            metadata.set_favorite(file, true);
            var query = new SearchQuery();
            query.text = "REPORT";
            query.kind = "PDF";
            query.minimum = 1024;
            query.maximum = 8192;
            query.after = 500;
            query.before = 1500;
            query.tag = "finance";
            query.favorites_only = true;
            query.owner = "alice";
            query.scope = "everywhere";
            assert(query.matches(item, metadata));
            var restored = SearchQuery.deserialize(query.serialize());
            assert(restored.matches(item, metadata));
            assert(restored.serialize() == query.serialize());
            assert(restored.scope == "everywhere");
            var legacy = "majoris-search-v1:" + new Variant("(ssttssttbs)", "report", "", (uint64)0, uint64.MAX, "Any", "modified", (uint64)0, uint64.MAX, false, "").print(true);
            assert(SearchQuery.deserialize(legacy).scope == "recursive");
            var multiline = new SearchQuery();
            multiline.tag = "Line\nTwo";
            multiline.owner = "Someone\nElse";
            multiline.content = "Text\nText";
            var multiline_saved = SearchQuery.deserialize(multiline.serialize());
            assert(multiline_saved.tag == multiline.tag && multiline_saved.owner == multiline.owner && multiline_saved.content == multiline.content);
            restored.kind = "Folder";
            assert(!restored.matches(item, metadata));
            restored.kind = "PDF";
            restored.date_field = "created";
            assert(!restored.matches(item, metadata));
            restored.date_field = "modified";
            restored.tag = "Financial";
            assert(!restored.matches(item, metadata));
            restored.tag = "finance";
            restored.minimum = 8192;
            assert(!restored.matches(item, metadata));
            assert(SearchQuery.deserialize("legacy filename").text == "legacy filename");
            bool rejected = false;
            try { SearchQuery.deserialize("majoris-search-v1:invalid");
            }
            catch(Error e) { rejected = true;
            }
            assert(rejected);
        }
        catch(Error e) { error("%s", e.message);
        }
    });
    Test.add_func("/metadata/tags-and-recovery", () => {
        try {
            var temp = DirUtils.make_tmp("majoris-meta-recovery-XXXXXX");
            var path = Path.build_filename(temp, "metadata.db");
            FileUtils.set_contents(path, "invalid database");
            var store = new MetadataStore(path);
            assert(!store.available);
            var backup = store.recover();
            assert(store.available);
            string preserved;
            FileUtils.get_contents(backup, out preserved);
            assert(preserved == "invalid database");
            var file = File.new_for_path("/tmp/tagged");
            store.set_tags(file, "Work,Finance");
            store.define_tag("Work", "#ff0000", 2);
            store.define_tag("Finance", "#00ff00", 1);
            assert(store.all_tags()[0] == "Finance");
            store.rename_tag("Work", "Projects");
            assert(store.tags(file) == "Projects,Finance");
            assert(store.tag_color("Projects") == "#ff0000");
            store.delete_tag("Finance");
            assert(store.tags(file) == "Projects");
        }
        catch(Error e) { error("%s", e.message);
        }
    });
    Test.add_func("/accounts/platform-directory-parser", () => {
        var users = AccountDirectory.parse("alice:x:1000:1000:Alice Example,Office:/home/alice:/bin/sh\ninvalid:x:no:1000::/:/bin/false\nalice:x:2000:2000:Duplicate:/tmp:/bin/false\nroot:x:0:0:Root:/root:/bin/sh\n", true);
        assert(users.size == 2);
        assert(users[0].id == 1000 && users[0].name == "alice" && users[0].label.contains("Alice Example"));
        assert(users[1].id == 0);
        var groups = AccountDirectory.parse("staff:x:1000:alice\nbad:x:-1:\nnone:x:4294967295:\n", false);
        assert(groups.size == 1 && groups[0].id == 1000 && groups[0].name == "staff");
    });
    Test.add_func("/chooser/save-files-validation", () => {
        foreach (var name in new string[] {"../escape", "folder/file", ".", "..", ""})
        {
            var options = new VariantBuilder(VariantType.VARDICT);
            var names = new VariantBuilder(new VariantType("aay"));
            names.add_value(new Variant.bytestring(name));
            options.add("{sv}", "files", names.end());
            bool rejected = false;
            try { new ChooserOptions(true, options.end(), true); }
            catch (Error e) { rejected = true; }
            assert(rejected);
        }
        bool rejected = false;
        try { new ChooserOptions(true, new VariantBuilder(VariantType.VARDICT).end(), true); }
        catch (Error e) { rejected = true; }
        assert(rejected);
    });
    Test.add_func("/checksum/supplied-values", () => {
        try {
            string hash = string.nfill(64, 'a');
            assert(SplitService.expected_checksum(hash.up(), "file.txt", ChecksumType.SHA256) == hash);
            assert(SplitService.expected_checksum(hash + "  other.txt\n" + hash + " *file.txt\n", "file.txt", ChecksumType.SHA256) == hash);
            bool rejected = false;
            try { SplitService.expected_checksum(hash + "  other.txt", "file.txt", ChecksumType.SHA256); }
            catch (Error e) { rejected = true; }
            assert(rejected);
            rejected = false;
            try { SplitService.expected_checksum(hash + "\n" + hash, "file.txt", ChecksumType.SHA256); }
            catch (Error e) { rejected = true; }
            assert(rejected);
            assert(SplitService.expected_checksum(string.nfill(128, 'b'), "file.txt", ChecksumType.SHA512).length == 128);
        }
        catch (Error e) { error("%s", e.message); }
    });
    Test.add_func("/rename/templates-and-modes", () => {
        try {
            var info = new FileInfo(); info.set_name("photo.jpg"); info.set_display_name("photo.jpg"); info.set_file_type(FileType.REGULAR);
            var item = new FileItem(File.new_for_path("/tmp/photo.jpg"), info);
            assert(RenamePlan.name(item, 0, "photo", "holiday", 1, 3) == "holiday.jpg");
            assert(RenamePlan.name(item, 1, "Before-", "", 1, 3) == "Before-photo.jpg");
            assert(RenamePlan.name(item, 2, "-After", "", 1, 3) == "photo-After.jpg");
            assert(RenamePlan.name(item, 3, "{stem}-{counter}{extension}", "", 7, 3) == "photo-007.jpg");
            var metadata = new Gee.HashMap<string, string>(); metadata["Artist"] = "Artist"; metadata["Title"] = "Title";
            assert(RenamePlan.name(item, 6, "{artist}-{title}{extension}", "", 1, 3, metadata) == "Artist-Title.jpg");
            bool rejected = false;
            try { RenamePlan.name(item, 3, "{camera}.jpg", "", 1, 3); } catch (Error e) { rejected = true; }
            assert(rejected);
        }
        catch (Error e) { error("%s", e.message); }
    });
    return Test.run();
}
