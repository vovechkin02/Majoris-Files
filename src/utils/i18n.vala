namespace MajorisFiles {
    public class I18n : Object {
        public static void initialize()
        {
            Intl.setlocale(LocaleCategory.ALL, "");
            Intl.bindtextdomain("majoris-files", Environment.get_variable("MAJORIS_FILES_LOCALEDIR") ?? "/usr/share/locale");
            Intl.bind_textdomain_codeset("majoris-files", "UTF-8");
            Intl.textdomain("majoris-files");
        }
    }
}
