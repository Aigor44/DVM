@echo off

REM DVM virtual machine
REM Compile with LCCwin32: lc -e5 -nw dvm.c -s


setlocal
  SET INCLUDE=C:\opt\lcc-win64\include
  SET PATH=C:\opt\lcc-win64\bin

  rem -e5 Set the maximum error count to 5.  The compiler will stop after 5 errors.
  rem -nw No warnings will be emitted.
  rem -s  strip                              This is a LINKER FLAG and the linker is lcclnk.exe
  lc -e5 -nw dvm.c -s
endlocal
