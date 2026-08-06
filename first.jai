main :: () {
    set_build_options_dc(.{do_output=false});
    workspace := compiler_create_workspace();

    options := get_build_options(workspace);
    options.output_executable_name = "replace";

    args := options.compile_time_command_line;

    optimize, _ := array_find(args, "o");
    if optimize {
        set_optimization(*options, Optimization_Type.VERY_OPTIMIZED, true);
    } else {
        set_optimization(*options, Optimization_Type.VERY_DEBUG, true);
    }

    set_build_options(options, workspace); 

    compiler_begin_intercept(workspace);
    add_build_file("main.jai", workspace);

    while true {
        message := compiler_wait_for_message();
        if !message break;
        if message.kind == {
            case .COMPLETE;
                break;
        }
    }
    compiler_end_intercept(workspace);

    should_run_tests, _ := array_find(args, "test");
    should_record_tests, _ := array_find(args, "record");

    if should_run_tests || should_record_tests {
        run_tests(should_record_tests);
        exit(0);
    }
}

run_tests :: (record: bool) {
    TESTS_FOLDER :: "tests";

    record_test :: (directory: string, data_folder: string, expected_file: string, command_file: string) {
        command, success := read_entire_file(command_file, zero_terminated = true);
        defer free(command);
        if !success {
            print_color("%: FAIL: command.txt is missing\n\n", data_folder, color = .RED);
            return;
        }

        command_arguments := split(command, "\n");

        print("running command: %\n", command_arguments);
        command_result, result, error := run_command(..command_arguments, capture_and_return_output = true);
        // if command_result.exit_code != 0 {
        //     print_color("%: FAIL: command % failed: % %\n", data_folder, command_arguments, command_result, error, color = .RED);
        //     return;
        // }

        success = write_entire_file(expected_file, result);
        if !success {
            print_color("%: FAIL: expected.txt is missing\n", data_folder, color = .RED);
            return;
        }

        print_color("%: Recorded contents:\n\n", directory, color = .GREEN);
        print("%\n", result);
    }

    run_test :: (directory: string, data_folder: string, expected_file: string, command_file: string) {
        command, success := read_entire_file(command_file, zero_terminated = true);
        defer free(command);
        if !success {
            print_color("%: FAIL: command.txt is missing\n\n", data_folder, color = .RED);
            return;
        }
        command = trim(command);

        expected:, success = read_entire_file(expected_file);
        defer free(expected);

        if !success {
            print_color("%: FAIL: expected.txt is missing\n\n", data_folder, color = .RED);
            return;
        }

        command_arguments := split(command, "\n");
        print("running command: %\n", command_arguments);
        command_result, result, error := run_command(..command_arguments, capture_and_return_output = true);

        // if command_result.exit_code != 0 {
        //     print_color("%: FAIL: command failed: % reasons: % %\n", data_folder, command_arguments, command_result, error, color = .RED);
        //     return;
        // }

        if result == expected {
            print_color("%: OK\n", directory, color = .GREEN);
        } else {
            print_color("%: FAIL: result (% bytes) != expected (% bytes)\n\n", data_folder, result.count, expected.count, color = .RED);
            print_color("RESULT\n", color = .BLUE);
            print("%\n", result);
            print_color("EXPECTED\n", color = .BLUE);
            print("%\n", expected);
        }
    }

    visit_files(TESTS_FOLDER, recursive = false, user_data = record, proc = (info: *File_Visit_Info, should_record_test: bool) {
        builder: String_Builder;
        append(*builder, info.full_name);
        append(*builder, "/data");
        data_folder := builder_to_string(*builder);

        append(*builder, info.full_name);
        append(*builder, "/expected.txt");
        expected_file := builder_to_string(*builder);

        append(*builder, info.full_name);
        append(*builder, "/command.txt");
        command_file := builder_to_string(*builder);

        if should_record_test {
            record_test(info.full_name, data_folder, expected_file, command_file);
        } else {
            run_test(info.full_name, data_folder, expected_file, command_file);
        }
    }, visit_files = false, visit_directories = true);

    // TODO: add testing for each configuration (navigation-style and such)

    // record:
    // replace -s -d tests/1/data/ "q" > tests/1/expected.txt

    // play:
    // replace -s -d tests/1/data/ "q" > tests/1/result.txt
    // diff tests/1/expected.txt tests/1/result.txt
}

#run main();

#import "Basic";
#import "Compiler";
#import "Process";
#import "Print_Color";
#import "String";
#import "File";
#import "File_Utilities";
