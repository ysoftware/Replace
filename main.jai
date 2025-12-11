main :: () {
    args := get_command_line_arguments();
    if args.count < 3 {
        print_help(args);
        exit(1);
    }

    if args.count < 3 {
        print_help(args);
        exit(1);
    }

    query := "";
    replace := "";
    directory := "";
    force := false;
    help := false;

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
                print("Error: Unexpected extra argument '%'.\nPrinting help...\n\n", args[i]);
                print_help(args);
                exit(1);
            }
        }

        i += 1;
    }

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
        unprotected_files_result := trim(output_string);

        if unprotected_files_result.count > 0 {
            unprotected_files := split(unprotected_files_result, "\n");
            if unprotected_files.count > 0 {
                // print("Detected unstaged or untracked changes in the git repository! Please stage them or use -f to ignore this warning.\n");
                // for unprotected_files {
                //     print("- %\n", it);
                // }
                // exit(1);
            }
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

    for list_of_files {
        // TODO: preview of all replacements before commiting (important for -f, otherwise can use git after the fact)
        contents, ok := read_entire_file(it, zero_terminated = false, log_errors = false);

        // filter out binary files
        if find_index_from_left(contents, byte = 0) != -1  continue;

        offset := 0;
        while contents.count > 0 {
            start, found := find_next_match(contents, query, offset);
            if !found  break;
            offset = start + query.count;

            match_string := string .{ data = contents.data + start - 20, count = query.count + 40 };
            print("Match:\n%\n\n", match_string);
        }

        print("% - % bytes\n", it, contents.count);
    }
}

find_next_match :: (contents: string, query: string, offset: s64) -> (start: s64, found: bool) {
    index := find_index_from_left(contents, query, offset);
    if index == -1  return 0, false;
    return index, true;
}

print_help :: (args: []string) {
    print("This tool literally replaces occurences of a string with another string inside of files found recursively in directory.\n");
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

// TODO: maybe filter files according to .ignore file

// written using jai compiler 0.2.021
#import "Basic";
#import "Process";
#import "String";
#import "System";
#import "File_Utilities";
#import "File";
