--****
-- === dsearch.exw 
--  
-- search for a .DLL that contains a given routine 
-- ==== Usage 
-- {{{ 
-- eui dsearch [-l|--lib library_list] [routine]  
-- }}} 
-- 
-- If you don't supply a string on the command line you will be prompted  
-- for it.  
-- 

-- If you do not supply a list of libraries a list will be scanned from
-- c:\\WINDOWS\System32, /usr/lib and /usr/local/lib.  The program will handle
-- empty or missing directories.

--
-- To trigger the dl-open bug, run on Linux with: eui dsearch.ex --lib libkorganizer_interfaces.so foo
--
include std/filesys.e 
include std/dll.e 
include std/machine.e 
include std/sequence.e
include std/error.e
include std/io.e

with trace

constant KEYBOARD = 0, SCREEN = 1, ERROR = 2

type enum boolean 
	TRUE = 1, FALSE = 0 
end type 

sequence cmd, orig_string 
 
integer scanned, no_open 
scanned = 0 
no_open = 0 
 
object library_list = 0 -- list of libraries to open.
 
atom string_pointer 
sequence routine_name 

-- because various operating systems use distinct extensions for dlls we cannot 
-- use *.so in the library listing.  So, we must later ignore if it cannot open 
-- files (as we don't know which ones are valid) 
sequence file_list
boolean be_verbose = FALSE, batch = FALSE

cmd = command_line()   -- eui dsearch [string] 
procedure print_usage()
        printf(ERROR, "usage : eui dsearch.ex [--help|-h] [--batch|-b] [--verbose|-v] [--lib librarylist|-llibrarylist] [routine_name]\n")
        puts(ERROR,   
`

        -h | --help    : this help message
        -b | --batch   : do not wait for keyboard input.  Just print result and exit.
        -v | --verbose : be verbose
        -l | --lib     : specify a list of libraries separated by commas even with spaces
        -x | --no-lib  : specify a list of libraries separated by commas that should not be tried


`)
end procedure

-- Parse the command line
integer argi = 3
while argi <= length(cmd) do
    sequence arg = cmd[argi]
    boolean arg_is_short = not equal(head(arg,2),"--")
    integer short_letter
    
    if length(arg)>1 and arg_is_short then
        short_letter = arg[2]
    else
        short_letter = 0
    end if
    
    if equal(arg,"--lib") or (short_letter = 'l') then
        -- library is the only one that takes an argument so this one must come first...
        if atom(library_list) then
             library_list = {}
        end if
        -- short argument...
        -- l_location != 0
        -- convert -lxxxxxx to -l xxxxxxx
        if arg_is_short and length(arg) != 2 then
            cmd = cmd[1..argi-1] & {arg[1..2]} & {arg[3..$]} & cmd[argi+1..$]
        end if
        loop do
            argi += 1
            if argi > length(cmd) then
                exit
            end if
            arg = cmd[argi]
            
            if arg[$] = ',' then
                library_list &= split(arg[1..$-1], ",")
                continue
            end if
            library_list &= split(arg, ",")
        until TRUE
        end loop
    elsif equal(arg, "--help") or (short_letter = 'h') then
        print_usage()
        abort(1)
    elsif equal(arg, "--verbose") or (short_letter = 'v') then
        if arg_is_short and length(arg) != 2 then
            cmd = cmd[1..argi-1] & {arg[1..2],'-' & arg[3..$]} & cmd[argi+1..$]
        end if
        be_verbose = TRUE
    elsif equal(arg,"--batch") or (short_letter = 'b') then
        batch = TRUE
        if arg_is_short and length(arg) != 2 then
            cmd = cmd[1..argi-1] & {"-b",'-' & arg[3..$]} & cmd[argi+1..$]
        end if
    elsif equal(arg,"--no-lib") or (short_letter = 'x') then
        if atom(library_list) then
            library_list = scan_default_libraries()
        end if
        if arg_is_short and length(arg) != 2 then
            cmd = cmd[1..argi-1] & {arg[1..2]} & {arg[3..$]} & cmd[argi+1..$]
        end if
        loop do
            sequence to_remove = {}
            argi += 1
            if argi > length(cmd) then
                exit
            end if
            arg = cmd[argi]
            
            if arg[$] = ',' then
                to_remove &= split(arg[1..$-1], ",")
                continue
            end if
            to_remove &= split(arg, ",")
            for li = 1 to length(to_remove) do
                integer j = find(to_remove[li], library_list)
                if j then
                    library_list = remove(library_list, j)
                end if
            end for
        until TRUE
        end loop      
    elsif object(orig_string) then
        printf(ERROR, "Error: routine specified twice: \n", {})
        print_usage()
        abort(1)
    else
        orig_string = arg
    end if
    argi += 1
end while

if not object(orig_string) then 
    puts(SCREEN, "C function name:")
    orig_string = delete_trailing_white(gets(KEYBOARD))
    puts(SCREEN, '\n') 
end if 

if atom(library_list) then
    library_list = scan_default_libraries()
end if

ifdef LINUX then
    constant DLL_EXT = "so"

trace(1)
    
    -- good for 32 and 64 bit
    -- these could be wrong on 64 bit Linux. I don't know.
    -- from /usr/include/bits/dlfcn.h
    constant RTLD_LAZY  = 1
    constant RTLD_LOCAL = 0
    constant RTLD_NOLOAD = 8,
             RTLD_GLOBAL = #100
    constant DYNAMIC_LINK_LIBRARY = "libdl.so.2"

    constant libdl = open_dll(DYNAMIC_LINK_LIBRARY)  
    constant dlopen_sym = define_c_func(libdl, "dlopen", {C_POINTER, C_INT}, C_POINTER)
    constant dlsym_sym  = define_c_func(libdl, "dlsym", {C_POINTER, C_POINTER}, C_POINTER)
    constant dlerror_sym = define_c_func(libdl, "dlerror", {}, C_POINTER)
    constant dlclose_sym = define_c_func(libdl, "dlclose", {C_POINTER}, C_INT)
    
    if libdl = 0 or find(-1, dlopen_sym & dlsym_sym & dlerror_sym & dlclose_sym) != 0 then
       puts(ERROR, "Cannot get dynamic link functions from "&DYNAMIC_LINK_LIBRARY&"\n")
       abort(1)
    end if 
    
    -- close an opened library
    procedure dl_close_library(atom lib)
        c_func(dlclose_sym, {lib})
    end procedure        
    
    -- return 0 on error; positive value on success
    function dl_open_library(sequence name)
        atom lib = c_func(dlopen_sym, {allocate_string(name, TRUE), or_bits(RTLD_LAZY, RTLD_LOCAL)})
        if lib != 0 then
            return delete_routine( lib, routine_id("dl_close_library") )
        end if
        return lib
    end function
    
    -- return -1 on error; non-negative on success
    function dl_get_symbol(atom handle, sequence name)
        atom e = c_func(dlerror_sym, {})
        atom ret = c_func(dlsym_sym, {handle, allocate_string(name, TRUE)})
        e = c_func(dlerror_sym,{})
        if e != 0 then
            return -1
        end if
        return ret
    end function
    
    if dl_open_library(DYNAMIC_LINK_LIBRARY) = 0 then
        puts(ERROR, "dl_open_library can't open what open_dll can.\n")
        atom error_value = c_func(dlerror_sym,{})
        if error_value then
            puts(ERROR, peek_string(error_value) & 10)
        end if
        abort(1)
    end if
    
    
    
elsifdef WINDOWS then
    constant DLL_EXT = "dll"

    -- return 0 on error positive value on success
    function dl_open_library(sequence name)
        return open_dll(name)
    end function
    
    -- return -1 on error non-negative value on success
    function dl_get_symbol(atom handle, sequence name)
        and_bits(define_c_var(handle, name), 
    end function    

elsedef

    -- return 0 on error positive value on success
    function dl_open_library(sequence name)
        return open_dll(name)
    end function
    
    -- return -1 on error non-negative value on success
    function dl_get_symbol(atom handle, sequence name)
        return define_c_var(handle, name)
    end function    
    
end ifdef




function scan_default_libraries()
    -- scan file list for libraries
    sequence filepath_list = {}
    object filemeta_list = {}
    sequence path_list = split(`c:\windows\system,/usr/lib,/usr/local/lib`, ',')
    
    for h = 1 to length(path_list) do
        filemeta_list = dir(path_list[h])
        if atom(filemeta_list) then
            continue
        end if
        for i = 1 to length(filemeta_list) do 
            if atom(filemeta_list[i]) then 
                continue
            end if
            sequence file = filemeta_list[i]
            if find('d', file[D_ATTRIBUTES]) then
                continue
            end if
            sequence file_name = file[D_NAME]
            if compare( filesys:fileext(file_name), DLL_EXT) then
                continue
            end if
            filepath_list = append( filepath_list, path_list[h] & filesys:SLASH & file_name )
        end for
    end for
    return filepath_list
end function

 
 
function scan(sequence file_name) -- as boolean 
-- process an eligible file 
    atom lib
    if be_verbose then
		puts(SCREEN, file_name & ": opening...")
	end if
	io:flush(SCREEN)
    lib = dl_open_library(file_name)
    
    if lib = 0 then
		no_open += 1 
		if be_verbose then
			puts(SCREEN, "failed.\n")
		else
			puts(SCREEN, file_name & ": Couldn't open.\n") 
		end if
		io:flush(SCREEN)
		return FALSE
	elsif be_verbose then
		puts(SCREEN, "success.")
		io:flush(SCREEN)
    end if
    scanned += 1
    if be_verbose then
    	printf(SCREEN, ".. accessing %s...", {routine_name})
		io:flush(SCREEN)
    end if
    if dl_get_symbol(lib, routine_name) != -1 then
    	if be_verbose then
    		printf(SCREEN, "success!\n", {})
    	else
			printf(SCREEN, "%s: ", {file_name})
			printf(SCREEN, "\n\n%s was FOUND in %s\n", {routine_name, file_name})
		end if
        io:flush(SCREEN)
		return TRUE
	elsif be_verbose then
		puts(SCREEN, "failure.\n")
        io:flush(SCREEN)
    end if
    return FALSE
end function

function delete_trailing_white(sequence name) -- as sequence 
-- get rid of blanks, tabs, newlines at end of string 
    while length(name) > 0 do 
	if find(name[length(name)], "\n\r\t ") then 
	    name = name[1..length(name)-1] 
	else 
	    exit 
	end if 
    end while 
    return name 
end function 
 
routine_name = orig_string 
 
procedure locate(sequence name) 
    routine_name = name 
    if be_verbose then
        puts(SCREEN, "Looking for " & routine_name & "\n ")
    end if
    for i = 1 to length(library_list) do 
	if scan(library_list[i]) then
	    if not batch then
	        puts(SCREEN, "Press Enter\n")
	        getc(KEYBOARD)
	    end if
	    abort(1) 
	end if 
    end for 
    if be_verbose then
        puts(SCREEN, '\n')
    end if
end procedure 
 
if length(routine_name) = 0 then 
    abort(0) 
end if 
 
locate(orig_string) 
ifdef WINDOWS then 
	locate(orig_string & "A") 
	locate(orig_string & "Ex") 
	locate(orig_string & "ExA") 
end ifdef 
 
puts(SCREEN, "\nCouldn't find " & orig_string & '\n')
if not batch then
    puts(SCREEN, "Press Enter\n") 
    if getc(KEYBOARD) then 
    end if
end if
