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

    if query == replace {
        print("Both strings are the same. Nothing to do.\n");
        exit(0);
    }

    if help {
        print_help(args);
        exit(0);
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
                print("Detected unstaged or untracked changes in the git repository! Please stage them or use -f to ignore this warning.\n");
                for unprotected_files {
                    print("- %\n", it);
                }
                exit(1);
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

    print("Searching folder %\n", directory);

    matched_files_count := 0;
    total_matches_count := 0;

    for list_of_files {
        if it[0] == #char "." continue;

        contents, ok := read_entire_file(it, zero_terminated = false, log_errors = false);
        defer free(contents.data);

        if find_index_from_left(contents, byte = 0) != -1  continue; // filter out binary files

        reached_eof := false;
        did_print_file_name := false;
        content_offset := 0;
        line_number := 1;
        is_even_color := true;
        while content_offset < contents.count {
            color: Console_Color = ifx is_even_color then .GREEN else .BLUE;

            line_end := find_index_from_left(contents, #char "\n", content_offset);
            if line_end == -1 {
                line_end = contents.count-1;
                reached_eof = true;
            }
            line := string.{ data = *contents[content_offset], count = line_end - content_offset + 1 }; // +1 to include new line
            content_offset += line.count;

            line_offset := 0;
            did_print_line_number := false;
            while true {
                match_index := find_index_from_left(line, query, line_offset);
                if match_index == -1 {
                    if did_print_line_number {
                        print("%", string.{ data = line.data + line_offset, count = line.count - line_offset });
                    }
                    break;
                }

                if !did_print_file_name {
                    did_print_file_name = true;
                    print("\n%\n", it);
                }
                if !did_print_line_number {
                    is_even_color = !is_even_color;
                    did_print_line_number = true;
                    print_color("%: ", FormatInt.{ value = line_number, minimum_digits = 6, padding = " " }, color = color);
                }

                prefix := string.{ data = line.data + line_offset, count = match_index - line_offset };
                print("%", trim_left(prefix));
                print_color("%", query, color = color);

                line_offset += match_index - line_offset + query.count;
                total_matches_count += 1;
            }

            line_number += 1;

            if reached_eof  break;
            continue;
        }

        if did_print_file_name {
            matched_files_count += 1;
        }
    }

    match_word := ifx total_matches_count == 1 then "match" else "matches";
    file_word := ifx matched_files_count == 1 then "file" else "files";
    print("\nFound % % in % %\n", total_matches_count, match_word, matched_files_count, file_word);
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

// TODO: option to disable colored output
// TODO: option to print file name together with file number (for emacs/vim navigation)
// TODO: option to ask to approve for every file before making the change
// TODO: use multithreading
// TODO: maybe filter files according to .ignore file
// TODO: maybe restrict some characters in query, like newline
// TODO: don't print lines that are too long (longer than 300 characters) - split them into multiple matches
// TODO: replace 'files' command
// TODO: check if git is installed

// written using jai compiler 0.2.021

#import "Basic";
#import "Process";
#import "String";
#import "System";
#import "File_Utilities";
#import "File";
#import "Print_Color";
