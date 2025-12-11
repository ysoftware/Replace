main :: () {
    args := get_command_line_arguments();
    if args.count < 3 {
        print_help(args);
        exit(1);
    }

    ok, query, replace, directory, force, help := parse_arguments(args);
    if !ok exit(1);
    if help {
        print_help(args);
        exit(1);
    }

    _, output_string, _, _ := run_command("git", "rev-parse", "--show-toplevel", capture_and_return_output = true);
    git_root := trim(output_string);

    if directory.count == 0 {
        directory = git_root;
    }

    if !force {
        if git_root.count == 0 {
            print("Git repository was not detected. To prevent loss of data, use git or pass -f to ignore this warning.\n");
            exit(1);
        }

        _, output_string, _, _ := run_command("git", "ls-files", "--others", "--modified", "--exclude-standard", capture_and_return_output = true);
        unprotected_files := split(trim(output_string), "\n");

        if unprotected_files.count > 0 {
            print("Detected unstaged or untracked changes in the git repository! Please stage them or use -f to ignore this warning.\n");
            for unprotected_files {
                print("- %\n", it);
            }
            exit(1);
        }
    }

    if directory.count == 0 {
        directory = get_working_directory();
    }

    list_of_files : []string;
    if git_root.count == 0 {
        list_of_files = file_list(directory, recursive = true, follow_directory_symlinks = false);
    } else {
        _, output_string, _, _ := run_command("git", "ls-files", "--exclude-standard", capture_and_return_output = true);
        list_of_files = split(trim(output_string), "\n");
    }

    print("All files:\n");
    for list_of_files {
        print("%\n", it);
    }
}

parse_arguments :: (args: []string) -> (ok: bool, query: string, replace: string, directory: string, force: bool, help: bool) {
    query := "";
    replace := "";
    directory := "";
    force := false;
    help := false;

    if args.count < 3 {
        return false, query, replace, directory, force, help;
    }

    i := 1;
    while (i < args.count) {
        if args[i] == "-d" {
            i += 1;
            directory = args[i];
        } else if args[i] == "-f" {
            force = true;
        } else if args[i] == "-h" {
            help = true;
        } else {
            if query.count == 0 {
                query = args[i];
            } else if (replace.count == 0) {
                replace = args[i];
            } else {
                print("Unexpected argument %.\n", args[i]);
                return false, query, replace, directory, force, help;
            }
        }

        i += 1;
    }
    return true, query, replace, directory, force, help;
}

// TODO: preview of all replacements before commiting (important for -f, otherwise can use git after the fact)
// TODO: decide how to operate on ignored and untracked files
// TODO: maybe filter files according to .ignore file
print_help :: (args: []string) {
    print("Literally replaces occurences of a string with another string inside of files found recursively in directory.\n");
    print("By default finds and uses the git root of the current working directory.\n");
    print("\n");
    print("To prevent loss of data, by default refuses to run outside of a git repository or with other unstaged or untracked changes inside of the git repository.\n");
    print("\n");
    print("Usage: % [options] <replace_this> <with_this>\n", args[0]);
    print("  -d: folder to search for files\n");
    print("  -f: run without checking git\n");
    print("  -h: print this help message\n");
    print("\n");
    print("Example: % print printf\n", args[0]);
    print("Example: % -f -d ~/Documents/People/ \"Name Surnam\" \"Name Surname\"\n", args[0]);
}

// written using jai compiler 0.2.021
#import "Basic";
#import "Process";
#import "String";
#import "System";
#import "File_Utilities";
