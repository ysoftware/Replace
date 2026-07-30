main :: () {
    set_build_options_dc(.{do_output=false});
    workspace := compiler_create_workspace();

    options := get_build_options(workspace);
    options.output_executable_name = "replace";

    args := options.compile_time_command_line;

    run_tests, _ := array_find(args, "test");
    if run_tests {
        print("running tests not implemented yet\n");

        // TODO: add testing for each configuration (navigation-style and such)

        // record:
        // replace -s -d tests/1/data/ "q" > tests/1/expected.txt

        // play:
        // replace -s -d tests/1/data/ "q" > tests/1/result.txt
        // diff tests/1/expected.txt tests/1/result.txt

        exit(0);
    }

    optimize, _ := array_find(args, "o");
    if optimize {
        set_optimization(*options, Optimization_Type.VERY_OPTIMIZED, true);
    } else {
        set_optimization(*options, Optimization_Type.VERY_DEBUG, true);
    }

    set_build_options(options, workspace); 
    add_build_file("main.jai", workspace);
}

#run main();

#import "Basic";
#import "Compiler";
