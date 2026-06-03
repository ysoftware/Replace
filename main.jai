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
    only_search := false;
    navigation_style_print := false;
    approve := true;
    ignore_git := false;
    help := false;

    i := 1;
    while (i < args.count) {
        if args[i] == "-d" {
            i += 1;
            if args.count > i {
                directory = args[i];
            } else {
                print_help(args);
                exit(1);
            }
        } else if args[i] == "-y" {
            approve = false;
        } else if args[i] == "-s" {
            only_search = true;
        } else if args[i] == "-n" {
            navigation_style_print = true;
        } else if args[i] == "-i" {
            ignore_git = true;
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

    if only_search {
        ignore_git = true;
    }

    if query == "" {
        print_help(args);
        exit(0);
    }

    if replace == "" && !only_search {
        print_help(args);
        exit(0);
    }

    if query == replace {
        print("Both strings are the same. Nothing to do.\n");
        exit(0);
    }

    if help {
        print_help(args);
        exit(0);
    }

    // find directory -----------------

    _, output_string, _, _ := run_command("git", "rev-parse", "--show-toplevel", capture_and_return_output = true);
    git_root := trim(output_string);
    if git_root.count > 0  set_working_directory(git_root);

    if !ignore_git { // check that we don't have any unprotected files, unless we ignore this rule
        if git_root.count == 0 {
            print("Git repository was not detected. To prevent loss of data, use git or pass -i to ignore this warning.\n");
            exit(1);
        }

        _, output_string, _, _ := run_command("git", "ls-files", "--others", "--modified", "--exclude-standard", capture_and_return_output = true);
        unprotected_files_result := trim(output_string);

        if unprotected_files_result.count > 0 {
            unprotected_files := split(unprotected_files_result, "\n");
            if unprotected_files.count > 0 {
                print("Detected unstaged or untracked changes in the git repository! Please stage them or use -i to ignore this check.\n");
                for unprotected_files {
                    print("- %\n", it);
                }
                exit(1);
            }
        }
    }


    // prepare list of files ----------

    list_of_files : []string;
    if git_root.count == 0 {
        working_dir := get_working_directory(); // TODO: returns absolute path, which is not what I want.
        if !navigation_style_print  print("Searching folder %\n", working_dir);
        list_of_files = file_list(working_dir, recursive = true, follow_directory_symlinks = false);
    } else if directory.count > 0 {
        if !navigation_style_print  print("Searching folder %\n", directory);
        _, output_string, _, _ := run_command("git", "ls-files", "--exclude-standard", "--full-name", "--", directory, capture_and_return_output = true);
        list_of_files = split(trim(output_string), "\n");
    } else {
        _, output_string, _, _ := run_command("git", "ls-files", "--exclude-standard", "--full-name", capture_and_return_output = true);
        list_of_files = split(trim(output_string), "\n");
    }

    if list_of_files.count == 0 {
        print("No files found.\n");
        exit(0);
    }

    if !navigation_style_print  print("\n");

    // search for matches -------------

    files_arena: Flat_Pool;
    files_allocator := Allocator.{ proc = flat_pool_allocator_proc, data = *files_arena };
    defer fini(*files_arena);

    matches_arena: Flat_Pool;
    matches_allocator := Allocator.{ proc = flat_pool_allocator_proc, data = *matches_arena };
    defer fini(*matches_arena);

    matches: [..]MatchesOfOneFile;
    matches.allocator = matches_allocator;

    total_matches_count := 0;
    scanned_files_count := 0;
    for list_of_files {
        if it.count == 0  continue; // sometimes we get empty lines
        if it[0] == #char "." continue;

        file, ok := file_open(it, for_writing=false, keep_existing_content=false);
        if !ok continue;
        defer file_close(*file);

        file_size, ok= := file_length(file);
        if !ok continue;

        if file_size > 50000000 && !navigation_style_print {
            print("%: file is larger than 50 MB. Skipping.\n", it);
            continue;
        }

        reset(*files_arena, overwrite_memory = false);
        contents, ok= := read_entire_file(file, zero_terminated = false,, files_allocator);
        scanned_files_count += 1;

        if !ok || find_index_from_left(contents, byte = 0) != -1  continue; // filter out binary files

        reached_eof := false;
        did_add_match := false;
        content_offset := 0;
        line_number := 1;
        while content_offset < contents.count {
            line_end := find_index_from_left(contents, #char "\n", content_offset);
            if line_end == -1 {
                line_end = contents.count-1;
                reached_eof = true;
            }
            line := string.{ data = *contents[content_offset], count = line_end - content_offset + 1 }; // +1 to include new line

            line_offset := 0;
            while true {
                match_index := find_index_from_left(line, query, line_offset);
                if match_index == -1  break;

                if !did_add_match {
                    did_add_match = true;
                    array_add(*matches, .{ path = it });
                    matches[matches.count-1].matches.allocator = matches_allocator;
                }

                array_add(*matches[matches.count-1].matches, .{ offset = content_offset+match_index, line_number = line_number, line_offset = match_index+1 });
                prefix := string.{ data = line.data + line_offset, count = match_index - line_offset };

                line_offset += match_index - line_offset + query.count;
                total_matches_count += 1;
            }

            line_number += 1;
            content_offset += line.count;

            if reached_eof  break;
            continue;
        }

        if (did_add_match) {
            print_file_matches(query, matches[matches.count-1], contents, navigation_style_print);
        }
    }

    match_word := ifx total_matches_count == 1 then "match" else "matches";
    file_word := ifx matches.count == 1 then "file" else "files";
    total_word := ifx list_of_files.count == 1 then "file" else "files";

    if total_matches_count == 0 || !navigation_style_print || !only_search {
        print("Found % % in % % (scanned % out of % %)\n", total_matches_count, match_word, matches.count, file_word, scanned_files_count, list_of_files.count, total_word);
    }

    if only_search || matches.count == 0 || total_matches_count == 0 {
        exit(0);
    }

    // replace matches ----------------

    is_first_question := true;
    written_files_count := 0;

    for < matches {
        if approve {
            if !is_first_question {
                reset(*files_arena, overwrite_memory = false);
                contents, ok := read_entire_file(it.path, zero_terminated = false,, files_allocator);
                if !ok {
                    print("Could not read the file again. Interrupting.\n");
                    exit(1);
                }
                print_file_matches(query, it, contents, navigation_style_print);
            }

            if is_first_question {
                print("Replace all changes: [yes] to approve.");
                is_first_question = false;
            } else {
                print("Replace remaining: [yes] approve.     ");
            }
            if matches.count > 1 {
                print(" Per file: [a] to approve [s] to skip - next file: ");
                print_color("%", it.path, color = .YELLOW);
            }
            print(" Otherwise cancel.\nUser input: ");

            buffer: *u8 = alloc(256);
            fgets(buffer, 256, stdin);
            user_input := to_string(buffer);

            if user_input == "yes\n" {
                approve = false; // no need to approve anymore
            } else if user_input == "s\n" {
                print("\n");
                continue;
            } else if user_input != "a\n" {
                print("Cancelled.\n");
                exit(0);
            }
        }

        reset(*files_arena, overwrite_memory = false);
        contents, ok := read_entire_file(it.path, zero_terminated = false,, files_allocator);

        output := string.{ data = alloc(contents.count + it.matches.count * (replace.count - query.count),, files_allocator) };
        read_offset := 0;

        for it.matches {
            skip_data_length := it.offset - read_offset;
            memcpy(*output.data[output.count], *contents.data[read_offset], skip_data_length);
            output.count += skip_data_length;
            read_offset += skip_data_length;

            memcpy(*output.data[output.count], replace.data, replace.count);
            read_offset += query.count;
            output.count += replace.count;
        }

        memcpy(*output.data[output.count], *contents.data[read_offset], contents.count - read_offset);
        output.count += contents.count - read_offset;

        ok = write_entire_file(it.path, output);
        if !ok {
            print("Could not write to file %. Interrupting.\n", it.path);
            exit(1);
        }
        written_files_count += 1;
        print("Written %.\n", it.path);
    }

    print("Overall written % files.\n", written_files_count);
}

Match :: struct {
    offset: s64;
    line_number: s64;
    line_offset: s64;
}

MatchesOfOneFile :: struct {
    path: string;
    matches: [..]Match;
}

print_file_matches :: (query: string, file_matches: MatchesOfOneFile, contents: string, navigation_style_print: bool) {
    if file_matches.matches.count == 0  return;

    if !navigation_style_print {
        print_color("%\n", file_matches.path, color = .YELLOW);
    }

    last_line_number_printed := -1;

    for file_matches.matches {
        did_print_line_number := false;
        prefix := string.{ data = contents.data + it.offset - it.line_offset, count = it.line_offset };
        if navigation_style_print {
            print("%:%:% %", file_matches.path, it.line_number, it.line_offset, trim_left(prefix));
            print("%", query);
        } else {
            if last_line_number_printed != it.line_number {
                last_line_number_printed := it.line_number;
                print("%: ", FormatInt.{ value = it.line_number, minimum_digits = 6, padding = " " });
            }
            print("%", trim_left(prefix));
            print_color("%", query, color = .GREEN);
        }

        after_query_offset := it.offset + query.count;
        contents_after_query := string.{ data = *contents[after_query_offset], count = contents.count - after_query_offset - 1 };
        end_of_this_line := find_index_from_left(contents_after_query, #char "\n");
        if end_of_this_line == -1  end_of_this_line = contents_after_query.count;

        print("%\n", string.{ data = contents_after_query.data, count = end_of_this_line });
    }

    if !navigation_style_print  print("\n");
}

print_help :: (args: []string) {
    print("This tool literally replaces occurences of a string with another string in files found recursively in a directory.\n");
    print("By default it finds and uses the git root of the current working directory.\n");
    print("\n");
    print("To prevent loss of data it by default refuses to run outside of a git repository and when unstaged or untracked changes are present.\n");
    print("\n");
    print("Usage: % [options] <replace_this> <with_this>\n", args[0]);
    print("  -d: specify folder to search for files. default is git root, not the working directory\n");
    print("  -y: skip approval for changes to be written\n");
    print("  -i: set to run without checking git\n");
    print("  -h: set to print this help message\n");
    print("  -s: set to only search for file paths\n");
    print("  -n: set to present matches in a format compatible with vim/emacs navigation\n");
    print("\n");
    print("Example: % print printf\n", args[0]);
    print("Example: % -d ~/Documents/People/ \"Name Surame\" \"Name Surname\"\n", args[0]);
}

// TODO: write test cases to cover all variations (normal/git, root/cwd, -d/default)
// TODO: exclude directories (also multiple values). auto-exclude .git directory (unless added with -d .git)
// TODO: support multiple directories for search just by providing -d several times
// TODO: better error messages, not just print_help
// TODO: filter files using .ignore file
// TODO: use multithreading
// TODO: faster search algorithm
// TODO: maybe restrict some characters in query, like newline
// TODO: don't print lines that are too long (longer than 300 characters) - split them into multiple matches
// TODO: gracefully handle the case when git is not installed

// developed using jai compiler 0.2.029

#import "Basic";
#import "Process";
#import "String";
#import "System";
#import "File_Utilities";
#import "File";
#import "Print_Color";
#import "Flat_Pool";
#import "POSIX";
