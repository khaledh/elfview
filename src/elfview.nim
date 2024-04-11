import os, strformat, strutils, streams
import illwill

import std/[parseopt, paths]

type
  ElfHeader = object
    magic: array[4, char]
    class: uint8
    endianness: uint8
    version: uint8
    osabi: uint8
    abiversion: uint8
    pad: array[7, uint8]
    `type`: uint16
    machine: uint16
    version2: uint32
    entry: uint64
    phoff: uint64
    shoff: uint64
    flags: uint32
    ehsize: uint16
    phentsize: uint16
    phnum: uint16
    shentsize: uint16
    shnum: uint16
    shstrndx: uint16

  ElfType = enum
    None = (0'u16, "Unknown")
    Relocatable = (1, "Relocatable")
    Executable = (2, "Executable")
    Shared = (3, "Shared object")
    Core = (4, "Core")
  
  ElfMachine = enum
    None = (0'u16, "None")
    Sparc = (0x02, "Sparc")
    X86 = (0x03, "x86")
    Mips = (0x08, "MIPS")
    PowerPC = (0x14, "PowerPC")
    ARM = (0x28, "Arm")
    Sparc64 = (0x2b, "Sparc64")
    IA64 = (0x32, "IA-64")
    X86_64 = (0x3e, "x86-64")
    AArch64 = (0xb7, "AArch64")
    RiscV = (0xf3, "RISC-V")

  ElfSectionHeader {.packed.} = object
    nameoffset: uint32
    `type`: uint32
    flags: uint64
    vaddr: uint64
    offset: uint64
    size: uint64
    link: uint32
    info: uint32
    addralign: uint64
    entsize: uint64
  
  ElfSectionType = enum
    Null = (0'u32, "NULL")
    ProgBits = (1, "PROGBITS")
    SymTab = (2, "SYMTAB")
    StrTab = (3, "STRTAB")
    Rela = (4, "RELA")
    Hash = (5, "HASH")
    Dynamic = (6, "DYNAMIC")
    Note = (7, "NOTE")
    NoBits = (8, "NOBITS")
    Rel = (9, "REL")
    ShLib = (10, "SHLIB")
    DynSym = (11, "DYNSYM")
    InitArray = (14, "INIT_ARRAY")
    FiniArray = (15, "FINI_ARRAY")
    PreInitArray = (16, "PREINIT_ARRAY")
    Group = (17, "GROUP")
    SymTabShndx = (18, "SYMTAB_SHNDX")
    GnuAttributes = (0x6ffffff5, "GNU_ATTRIBUTES")
    GnuHash = (0x6ffffff6, "GNU_HASH")
    GnuLibList = (0x6ffffff7, "GNU_LIBLIST")
    CheckSum = (0x6ffffff8, "CHECKSUM")
    GnuVerDef = (0x6ffffffd, "GNU_VERDEF")
    GnuVerNeed = (0x6ffffffe, "GNU_VERNEED")
    GnuVerSym = (0x6fffffff, "GNU_VERSYM")


var filename: string

for kind, key, val in getopt():
  case kind
  of cmdArgument:
    filename = key
  of cmdLongOption, cmdShortOption:
    # case key:
    # of "varName": # --varName:<value> in the console when executing
    #   varName = val # do input sanitization in production systems
    discard
  of cmdEnd:
    discard

if filename.len == 0:
  echo "Usage: ", Path(getAppFilename()).lastPathPart.string, " <filename>"
  quit(1)

var f = newFileStream(filename)
var fileSize = os.getFileSize(filename)
var hdr: ElfHeader

f.read(hdr)

if hdr.magic != [0x7f.char, 'E', 'L', 'F']:
  echo "Not an ELF file"
  quit(1)

# if hdr.class == 1:
#   echo "32-bit ELF"
# elif hdr.class == 2:
#   echo "64-bit ELF"
# else:
#   echo "Invalid ELF class"

# if hdr.endianness == 1:
#   echo "Little-endian"
# elif hdr.endianness == 2:
#   echo "Big-endian"
# else:
#   echo "Invalid endianness"

# echo "Version: ", hdr.version

# if hdr.osabi == 0:
#   echo "OS/ABI: System V"
# else:
#   echo "OS/ABI: ", hdr.osabi

# echo "ABI version: ", hdr.abiversion

const
  Title = " ELF Viewer "

proc exitProc() {.noconv.} =
  illwillDeinit()
  showCursor()
  quit(0)

proc getSectionHeader(f: FileStream, hdr: ElfHeader, index: uint32): ElfSectionHeader =
  var sh: ElfSectionHeader
  f.setPosition(int(hdr.shoff + hdr.shentsize * index))
  f.read(sh)
  return sh

proc getSectionName(f: FileStream, sh: ElfSectionHeader): string =
  var shstrtab: ElfSectionHeader
  f.setPosition(int(hdr.shoff + hdr.shentsize * hdr.shstrndx))
  f.read(shstrtab)

  f.setPosition(int(shstrtab.offset + sh.nameoffset))
  var secname: string
  var ch = f.readChar()
  while ch != 0.char:
    secname.add(ch)
    ch = f.readChar()
  return secname


proc main() =
  illwillInit(fullscreen=true)
  setControlCHook(exitProc)
  hideCursor()

  var highlightedIndex = 0'u32

  while true:
    var tb = newTerminalBuffer(terminalWidth(), terminalHeight())

    var key = getKey()
    case key
    of Key.Escape, Key.Q: exitProc()
    of Key.Up:
      if highlightedIndex > 0:
        dec highlightedIndex
    of Key.Down:
      if highlightedIndex < hdr.shnum - 1:
        inc highlightedIndex
    else: discard

    var bb = newBoxBuffer(tb.width, tb.height)
    bb.drawRect(0, 0, tb.width-1, tb.height-1)
    bb.drawHorizLine(0, tb.width-1, 3)
    tb.setForegroundColor(fgYellow)
    tb.write(bb)

    tb.setForegroundColor(fgWhite)
    tb.write((terminalWidth() - Title.len) div 2, 0, Title)

    tb.write(2, 1, styleDim, "File: ", resetStyle, &"{filename}")
    tb.write(2, 2, styleDim, "Size: ", resetStyle, &"{formatSize(fileSize, includeSpace = true)}")
    tb.write(40, 1, styleDim, "Type: ", resetStyle, &"{cast[ElfType](hdr.type)}")
    tb.write(40, 2, styleDim, "Arch: ", resetStyle, &"{cast[ElfMachine](hdr.machine)}")
    tb.write(80, 2, styleDim, "Entry Point: ", resetStyle, &"{hdr.entry:#x}")

    tb.write(2, 4, &"Sections ({hdr.shnum})")
    tb.setStyle({styleDim})
    tb.write(5, 6, "Name")
    tb.write(30, 6, "Type")
    tb.write(54, 6, "Address")
    tb.write(67, 6, "Offset")
    tb.write(79, 6, "Size")
    tb.write(86, 6, "Flags")
    tb.write(92, 6, "Align")
    tb.resetAttributes()

    # read .shstrtab section header
    var shstrtab: ElfSectionHeader
    f.setPosition(int(hdr.shoff + hdr.shentsize * hdr.shstrndx))
    f.read(shstrtab)

    for i in 0'u32 ..< hdr.shnum:
      let sh = getSectionHeader(f, hdr, i)
      let secname = getSectionName(f, sh)

      let row = int(7+i)
      if i == highlightedIndex:
        tb.setForegroundColor(fgBlack)
        tb.setBackgroundColor(bgYellow)
        for j in 3..96:
          tb.write(j, row, " ")

      tb.write(2, row, &"{i+1:0>2}")
      tb.write(5, row, &"{secname}")
      tb.write(30, row, &"{cast[ElfSectionType](sh.type)}")

      if cast[ElfSectionType](sh.type) != ElfSectionType.Null:
        tb.write(45, row, &"{sh.vaddr:> 16x}")
        tb.write(65, row, &"{sh.offset:> 8x}")
        tb.write(75, row, &"{sh.size:> 8x}")

        var flags = ""
        if (sh.flags and 2) == 2:
          flags.add('A')
        else:
          flags.add(' ')
        if (sh.flags and 1) == 1:
          flags.add('W')
        else:
          flags.add(' ')
        if (sh.flags and 4) == 4:
          flags.add('X')
        else:
          flags.add(' ')
        tb.write(86, row, &"{flags}")

        tb.write(92, row, &"{sh.addralign:> 5}")

      if i == highlightedIndex:
        tb.resetAttributes()


    let sh = getSectionHeader(f, hdr, highlightedIndex)
    let secname = getSectionName(f, sh)

    var tbDetails = newTerminalBuffer(80, 40)

    var bbDetails = newBoxBuffer(tbDetails.width, tbDetails.height)
    bbDetails.drawRect(0, 0, tbDetails.width-1, tbDetails.height-1)
    bbDetails.drawHorizLine(0, tbDetails.width-1, 2)

    tbDetails.setForegroundColor(fgYellow)
    tbDetails.write(bbDetails)
    tbDetails.resetAttributes()
    tbDetails.write(1, 1, styleDim, "Section: ", resetStyle, &"{secname}")

    # show hex dump of section contents
    f.setPosition(int(sh.offset))
    var buf: array[16, uint8]
    for i in 0'u64 ..< sh.size:
      if i mod 16 == 0:
        f.read(buf)
        tbDetails.write(1, 3 + (i div 16), &"{i:08x}  ")
      tbDetails.write(11 + (i mod 16) * 3, 3 + (i div 16), &"{buf[i mod 16]:02x} ")
      if i mod 16 == 15 or i == sh.size - 1:
        for j in 0..15:
          if buf[j] < 32 or buf[j] > 126:
            buf[j] = 46'u8
          tbDetails.write(60+j, 3 + (i div 16), $(buf[j].char))

    tb.copyFrom(tbDetails, 0, 0, tbDetails.width, tbDetails.height, 1, 36)

    # tb.setBackgroundColor(bgRed)
    # tb.setForegroundColor(fgWhite, bright=true)
    # tb.write(1, 1, fmt"Width:  {tb.width}")
    # tb.write(1, 2, fmt"Height: {tb.height}")

    # tb.resetAttributes()
    # tb.write(1, 4, "Press Q, Esc or Ctrl-C to quit")
    # tb.write(1, 5, "Resize the terminal window and see what happens :)")

    tb.display()

    sleep(20)

main()
