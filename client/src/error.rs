//! VBScript runtime errors and the non-local control flow signals.

use std::rc::Rc;

/// A raised VBScript error, as observed through the `Err` object.
#[derive(Clone, Debug)]
pub struct VbError {
    /// The value `Err.Number` reports. Built-in errors use their short code
    /// (13, 9, ...); anything else keeps the raw HRESULT.
    pub number: i32,
    pub source: Rc<str>,
    pub description: Rc<str>,
    pub helpfile: Rc<str>,
    pub helpcontext: i32,
}

/// VBScript's own errors are HRESULTs in the 0x800A0000 facility; `Err.Number`
/// strips that prefix back off.
pub const VBS_FACILITY: i32 = 0x800A_0000u32 as i32;

pub fn hresult_to_number(hr: i32) -> i32 {
    let u = hr as u32;
    // VBScript's own facility carries the short code in the low word.
    if (0x800A_0000..=0x800A_FFFF).contains(&u) {
        return (u & 0xFFFF) as i32;
    }
    // Well-known system HRESULTs surface as the matching VB error code.
    if let Some(n) = HRESULT_MAP.iter().find(|(h, _)| *h == u).map(|(_, n)| *n) {
        return n;
    }
    hr
}

/// System HRESULTs that VBScript reports as one of its own error numbers.
const HRESULT_MAP: &[(u32, i32)] = &[
    (0x8000_4001, 445), // E_NOTIMPL
    (0x8000_4002, 430), // E_NOINTERFACE
    (0x8002_0001, 438), // DISP_E_UNKNOWNINTERFACE
    (0x8002_0003, 438), // DISP_E_MEMBERNOTFOUND
    (0x8002_0004, 448), // DISP_E_PARAMNOTFOUND
    (0x8002_0005, 13),  // DISP_E_TYPEMISMATCH
    (0x8002_0006, 438), // DISP_E_UNKNOWNNAME
    (0x8002_0007, 446), // DISP_E_NONAMEDARGS
    (0x8002_0008, 458), // DISP_E_BADVARTYPE
    (0x8002_000A, 6),   // DISP_E_OVERFLOW
    (0x8002_000B, 9),   // DISP_E_BADINDEX
    (0x8002_000C, 447), // DISP_E_UNKNOWNLCID
    (0x8002_000D, 10),  // DISP_E_ARRAYISLOCKED
    (0x8002_000E, 450), // DISP_E_BADPARAMCOUNT
    (0x8002_000F, 449), // DISP_E_PARAMNOTOPTIONAL
    (0x8002_0011, 451), // DISP_E_NOTACOLLECTION
    (0x8002_802F, 453), // TYPE_E_DLLFUNCTIONNOTFOUND
    (0x8002_8CA0, 13),  // TYPE_E_TYPEMISMATCH
    (0x8002_8CA1, 9),   // TYPE_E_OUTOFBOUNDS
    (0x8002_8CA2, 57),  // TYPE_E_IOERROR
    (0x8002_8CA3, 322), // TYPE_E_CANTCREATETMPFILE
    (0x8003_0002, 432), // STG_E_FILENOTFOUND
    (0x8003_0003, 76),  // STG_E_PATHNOTFOUND
    (0x8003_0004, 67),  // STG_E_TOOMANYOPENFILES
    (0x8003_0005, 70),  // STG_E_ACCESSDENIED
    (0x8003_0008, 7),   // STG_E_INSUFFICIENTMEMORY
    (0x8003_0012, 67),  // STG_E_NOMOREFILES
    (0x8003_0013, 70),  // STG_E_DISKISWRITEPROTECTED
    (0x8003_001D, 57),  // STG_E_WRITEFAULT
    (0x8003_001E, 57),  // STG_E_READFAULT
    (0x8003_0020, 75),  // STG_E_SHAREVIOLATION
    (0x8003_0021, 70),  // STG_E_LOCKVIOLATION
    (0x8003_0050, 58),  // STG_E_FILEALREADYEXISTS
    (0x8003_0070, 61),  // STG_E_MEDIUMFULL
    (0x8003_00FC, 53),  // STG_E_INVALIDNAME
    (0x8003_0100, 70),  // STG_E_INUSE
    (0x8003_0101, 70),  // STG_E_NOTCURRENT
    (0x8003_0103, 57),  // STG_E_CANTSAVE
    (0x8004_0154, 429), // REGDB_E_CLASSNOTREG
    (0x8004_01E3, 429), // MK_E_UNAVAILABLE
    (0x8004_01E6, 432), // MK_E_INVALIDEXTENSION
    (0x8004_01EA, 432), // MK_E_CANTOPENFILE
    (0x8004_01F3, 429), // CO_E_CLASSSTRING
    (0x8004_01F5, 429), // CO_E_APPNOTFOUND
    (0x8004_01FE, 429), // CO_E_APPDIDNTREG
    (0x8007_0005, 70),  // E_ACCESSDENIED
    (0x8007_000E, 7),   // E_OUTOFMEMORY
    (0x8007_0057, 5),   // E_INVALIDARG
    (0x8007_06BA, 462), // RPC_S_SERVER_UNAVAILABLE
    (0x8008_0005, 429), // CO_E_SERVER_EXEC_FAILURE
];

pub fn number_to_hresult(n: i32) -> i32 {
    if (0..=0xFFFF).contains(&n) {
        (0x800A_0000u32 | n as u32) as i32
    } else {
        n
    }
}

impl VbError {
    pub fn new(number: i32, description: impl AsRef<str>) -> VbError {
        VbError {
            number,
            source: Rc::from("Microsoft VBScript runtime error"),
            description: Rc::from(description.as_ref()),
            helpfile: Rc::from(""),
            helpcontext: 0,
        }
    }

    /// Build from a short VBScript code, filling in the standard description.
    pub fn code(number: i32) -> VbError {
        VbError::new(number, describe(number))
    }

    pub fn hresult(&self) -> i32 {
        number_to_hresult(self.number)
    }
}

/// The standard description text for a built-in error code.
pub fn describe(number: i32) -> &'static str {
    match number {
        5 => "Invalid procedure call or argument",
        6 => "Overflow",
        7 => "Out of memory",
        9 => "Subscript out of range",
        10 => "This array is fixed or temporarily locked",
        11 => "Division by zero",
        13 => "Type mismatch",
        14 => "Out of string space",
        17 => "Can't perform requested operation",
        28 => "Out of stack space",
        35 => "Sub or function not defined",
        48 => "Error in loading DLL",
        51 => "Internal error",
        52 => "Bad file name or number",
        53 => "File not found",
        57 => "Device I/O error",
        58 => "File already exists",
        61 => "Disk full",
        67 => "Too many files",
        68 => "Device unavailable",
        70 => "Permission denied",
        71 => "Disk not ready",
        74 => "Can't rename with different drive",
        75 => "Path/File access error",
        76 => "Path not found",
        91 => "Object variable not set",
        92 => "For loop not initialized",
        94 => "Invalid use of Null",
        322 => "Can't create necessary temporary file",
        424 => "Object required",
        429 => "ActiveX component can't create object",
        430 => "Class doesn't support Automation",
        432 => "File name or class name not found during Automation operation",
        438 => "Object doesn't support this property or method",
        440 => "Automation error",
        445 => "Object doesn't support this action",
        446 => "Object doesn't support named arguments",
        447 => "Object doesn't support current locale setting",
        448 => "Named argument not found",
        449 => "Argument not optional",
        450 => "Wrong number of arguments or invalid property assignment",
        451 => "Object not a collection",
        453 => "Specified DLL function not found",
        455 => "Code resource lock error",
        457 => "This key is already associated with an element of this collection",
        458 => "Variable uses an Automation type not supported in VBScript",
        462 => "The remote server machine does not exist or is unavailable",
        481 => "Invalid picture",
        500 => "Variable is undefined",
        501 => "Illegal assignment",
        502 => "Object not safe for scripting",
        503 => "Object not safe for initializing",
        504 => "Object not safe for creating",
        505 => "Invalid or unqualified reference",
        506 => "Class not defined",
        507 => "An exception occurred",
        1041 => "Name redefined",
        5016 => "Regular Expression object expected",
        5017 => "Syntax error in regular expression",
        5018 => "Unexpected quantifier",
        5019 => "Expected ']' in regular expression",
        5020 => "Expected ')' in regular expression",
        5021 => "Invalid range in character set",
        _ => "Unknown runtime error",
    }
}

/// Constructors for the errors raised throughout the interpreter.
pub mod err {
    use super::VbError;

    macro_rules! ctor {
        ($($name:ident => $code:expr),* $(,)?) => {
            $(pub fn $name() -> VbError { VbError::code($code) })*
        };
    }

    ctor! {
        invalid_call => 5,
        overflow => 6,
        out_of_memory => 7,
        subscript => 9,
        array_locked => 10,
        div_zero => 11,
        type_mismatch => 13,
        out_of_stack => 28,
        undefined_sub => 35,
        object_not_set => 91,
        for_not_initialized => 92,
        invalid_use_of_null => 94,
        object_required => 424,
        cant_create_object => 429,
        no_such_member => 438,
        not_supported => 445,
        named_arg_not_found => 448,
        arg_not_optional => 449,
        wrong_arg_count => 450,
        not_a_collection => 451,
        variable_undefined => 500,
        illegal_assignment => 501,
        invalid_reference => 505,
        class_not_defined => 506,
    }

    pub fn member_not_found(_name: &str) -> VbError {
        VbError::new(438, "Object doesn't support this property or method")
    }

    pub fn name_not_defined(_name: &str) -> VbError {
        VbError::new(500, "Variable is undefined")
    }

    pub fn sub_not_defined(name: &str) -> VbError {
        VbError::new(35, format!("Sub or function not defined: '{name}'"))
    }

    pub fn object_no_value() -> VbError {
        VbError::new(438, "Object doesn't support this property or method")
    }
}

pub type VbResult<T> = Result<T, VbError>;

/// Why a statement sequence stopped early.
#[derive(Debug)]
pub enum Flow {
    Error(VbError),
    ExitDo,
    ExitFor,
    ExitFunction,
    ExitSub,
    ExitProperty,
    /// `Stop` with no debugger attached simply ends the script.
    Halt,
}

impl From<VbError> for Flow {
    fn from(e: VbError) -> Flow {
        Flow::Error(e)
    }
}

pub type ExecResult = Result<(), Flow>;

/// A parse-time (compile) error. VBScript reports these before running.
#[derive(Debug)]
pub struct SyntaxError {
    pub msg: String,
    pub line: u32,
    /// The error number VBScript reports for this failure.
    pub code: i32,
}

impl std::fmt::Display for SyntaxError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "line {}: {}", self.line, self.msg)
    }
}

impl std::fmt::Display for VbError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Error {}: {}", self.number, self.description)
    }
}
