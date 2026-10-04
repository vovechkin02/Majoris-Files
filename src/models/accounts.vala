namespace MajorisFiles {
    public class SystemAccount : Object {
        public string name;
        public string label;
        public uint id;
        public SystemAccount(string name, string label, uint id)
        {
            this.name = name;
            this.label = label;
            this.id = id;
        }
    }
    public class AccountDirectory : Object {
        public static Gee.ArrayList<SystemAccount> parse(string text, bool users)
        {
            var result = new Gee.ArrayList<SystemAccount>();
            var seen = new Gee.HashSet<string>();
            foreach(var line in text.split("\n"))
            {
                var fields = line.split(":");
                uint id = 0;
                if(fields.length < (users ? 7 : 4) || fields[0] == "" || !Regex.match_simple("^[0-9]+$", fields[2]) || !uint.try_parse(fields[2], out id) || id == uint.MAX || !seen.add(fields[0]))
                    continue;
                string friendly = users ? fields[4].split(",")[0].strip() : "";
                string label = friendly == "" ? "%s · %u".printf(fields[0], id) : "%s (%s · %u)".printf(friendly, fields[0], id);
                result.add(new SystemAccount(fields[0], label, id));
                if(result.size >= 10000)
                    break;
            }
            result.sort((a, b) => Paths.natural_compare(a.label, b.label));
            return result;
        }
        public static async Gee.ArrayList<SystemAccount> load(bool users, Cancellable token) throws Error
        {
            token.set_error_if_cancelled();
            var executable = Environment.find_program_in_path("getent");
            if(executable == null)
                throw new FileError.UNSUPPORTED("Account lookup is unavailable; enter a numeric ID");
            var process = new Subprocess.newv({executable, users ? "passwd" : "group"}, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
            bool timed_out = false;
            uint timeout = Timeout.add_seconds(5, () => { timed_out = true;
                                                          process.force_exit();
                                                          return Source.REMOVE;
                });
            ulong cancellation = token.cancelled.connect(() => process.force_exit());
            uint8[] bytes = new uint8[1024 * 1024 + 1];
            size_t count = 0;
            try {
                yield process.get_stdout_pipe().read_all_async(bytes[0 : bytes.length - 1], Priority.LOW, token, out count);
                if(count == bytes.length - 1)
                    throw new FileError.UNSUPPORTED("Account directory exceeds the lookup limit; enter a numeric ID");
                yield process.wait_check_async(token);
                if(timed_out)
                    throw new IOError.TIMED_OUT("Account lookup took too long; enter a numeric ID");
                token.set_error_if_cancelled();
            }
            catch(Error e) {
                process.force_exit();
                if(!timed_out)
                    Source.remove(timeout);
                token.disconnect(cancellation);
                throw e;
            }
            if(!timed_out)
                Source.remove(timeout);
            token.disconnect(cancellation);
            bytes[count] = 0;
            return parse(((string)bytes).make_valid(), users);
        }
    }
}
