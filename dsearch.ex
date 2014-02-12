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


function scan_default_libraries()
    -- scan file list for libraries
    file_list = dir(`c:\windows\system32\*.dll`) & dir(`/usr/lib/*`)  
	& dir(`/usr/local/lib/*`)

    sequence list = {}
    for i = 1 to length(file_list) do 
        if atom(file_list[i]) then 
            continue
        end if
        sequence file = file_list[i]
        if find('d', file[D_ATTRIBUTES]) then
            continue
        end if
        sequence file_name = file[D_NAME]
        ifdef LINUX then
            if compare( tail(file_name, 3), ".so") then
                continue
            end if
        end ifdef
        list = append( list, file_name )
    end for
    return list
end function

 
 
function scan(sequence file_name) -- as boolean 
-- process an eligible file 
    atom lib
    if be_verbose then
		puts(SCREEN, file_name & ": opening...")
	end if
	io:flush(SCREEN)
    lib = open_dll(file_name)
    
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
    if define_c_var(lib, routine_name) != -1 then
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
