[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Path)

$ErrorActionPreference = 'Stop'
$resolved = (Resolve-Path -LiteralPath $Path).Path
$bytes = [IO.File]::ReadAllBytes($resolved)
function U16([int]$offset) { [BitConverter]::ToUInt16($bytes, $offset) }
function U32([int]$offset) { [BitConverter]::ToUInt32($bytes, $offset) }

if ($bytes.Length -lt 512 -or (U16 0) -ne 0x5A4D) { throw 'Not a valid DOS/PE image.' }
$pe = [int](U32 0x3C)
if ((U32 $pe) -ne 0x00004550) { throw 'PE signature is missing.' }
$sectionCount = U16 ($pe + 6)
$optionalSize = U16 ($pe + 20)
$optional = $pe + 24
if ((U16 $optional) -ne 0x20B) { throw 'Production build must be PE32+ (x64).' }
$sectionAlignment = U32 ($optional + 32)
$fileAlignment = U32 ($optional + 36)
$dllCharacteristics = U16 ($optional + 70)
$required = 0x20 -bor 0x40 -bor 0x80 -bor 0x100 -bor 0x4000
if ($sectionAlignment -lt 0x1000) { throw ('SectionAlignment is 0x{0:X}, expected at least 0x1000.' -f $sectionAlignment) }
if ($fileAlignment -lt 0x200) { throw ('FileAlignment is 0x{0:X}, expected at least 0x200.' -f $fileAlignment) }
if (($dllCharacteristics -band $required) -ne $required) {
    throw ('Missing required PE mitigations; DllCharacteristics=0x{0:X4}.' -f $dllCharacteristics)
}

$sectionTable = $optional + $optionalSize
for ($index = 0; $index -lt $sectionCount; $index++) {
    $offset = $sectionTable + (40 * $index)
    $nameBytes = $bytes[$offset..($offset + 7)]
    $name = ([Text.Encoding]::ASCII.GetString($nameBytes)).Trim([char]0)
    $characteristics = U32 ($offset + 36)
    if (($characteristics -band 0x20000000) -and ($characteristics -band 0x80000000)) {
        throw "Section '$name' is both writable and executable."
    }
}

[pscustomobject]@{
    Path = $resolved
    Machine = 'x64'
    SectionAlignment = ('0x{0:X}' -f $sectionAlignment)
    FileAlignment = ('0x{0:X}' -f $fileAlignment)
    DllCharacteristics = ('0x{0:X4}' -f $dllCharacteristics)
    WritableExecutableSections = 0
    Passed = $true
}
