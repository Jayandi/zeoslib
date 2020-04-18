{*********************************************************}
{                                                         }
{                 Zeos Database Objects                   }
{         Sybase SQL Anywhere Connectivity Classes        }
{                                                         }
{        Originally written by EgonHugeist                }
{                                                         }
{*********************************************************}

{@********************************************************}
{    Copyright (c) 1999-2012 Zeos Development Group       }
{                                                         }
{ License Agreement:                                      }
{                                                         }
{ This library is distributed in the hope that it will be }
{ useful, but WITHOUT ANY WARRANTY; without even the      }
{ implied warranty of MERCHANTABILITY or FITNESS FOR      }
{ A PARTICULAR PURPOSE.  See the GNU Lesser General       }
{ Public License for more details.                        }
{                                                         }
{ The source code of the ZEOS Libraries and packages are  }
{ distributed under the Library GNU General Public        }
{ License (see the file COPYING / COPYING.ZEOS)           }
{ with the following  modification:                       }
{ As a special exception, the copyright holders of this   }
{ library give you permission to link this library with   }
{ independent modules to produce an executable,           }
{ regardless of the license terms of these independent    }
{ modules, and to copy and distribute the resulting       }
{ executable under terms of your choice, provided that    }
{ you also meet, for each linked independent module,      }
{ the terms and conditions of the license of that module. }
{ An independent module is a module which is not derived  }
{ from or based on this library. If you modify this       }
{ library, you may extend this exception to your version  }
{ of the library, but you are not obligated to do so.     }
{ If you do not wish to do so, delete this exception      }
{ statement from your version.                            }
{                                                         }
{                                                         }
{ The project web site is located on:                     }
{   http://zeos.firmos.at  (FORUM)                        }
{   http://sourceforge.net/p/zeoslib/tickets/ (BUGTRACKER)}
{   svn://svn.code.sf.net/p/zeoslib/code-0/trunk (SVN)    }
{                                                         }
{   http://www.sourceforge.net/projects/zeoslib.          }
{                                                         }
{                                                         }
{                                 Zeos Development Group. }
{********************************************************@}

unit ZDbcSQLAnywhere;

{$I ZDbc.inc}

interface

{$IFNDEF ZEOS_DISABLE_ASA}
uses
  ZCompatibility, Classes, {$IFDEF MSEgui}mclasses,{$ENDIF}
  SysUtils,
  ZDbcIntfs, ZDbcConnection, ZPlainSQLAnywhere, ZTokenizer, ZDbcGenericResolver,
  ZGenericSqlAnalyser, ZDbcLogging;

type
  {** Implements a ASA Database Driver. }
  TZSQLAnywhereDriver = class(TZAbstractDriver)
  public
    constructor Create; override;
    function Connect(const Url: TZURL): IZConnection; override;
    function GetTokenizer: IZTokenizer; override;
    function GetStatementAnalyser: IZStatementAnalyser; override;
  end;

  IZSQLAnywhereConnection = Interface(IZConnection)
    ['{6464E444-68E8-4233-ABF0-3B820D40883F}']
    function Get_a_sqlany_connection: Pa_sqlany_connection;
    function Get_api_version: Tsacapi_u32;
    procedure HandleError(LogginCategory: TZLoggingCategory;
      const Msg: RawByteString; const ImmediatelyReleasable: IImmediatelyReleasable);
    function GetPlainDriver: TZSQLAnywherePlainDriver;
  End;

  {** Implements ASA Database Connection. }
  TZSQLAnywhereConnection = class(TZAbstractDbcConnection, IZConnection,
    IZTransaction, IZSQLAnywhereConnection)
  private
    FPlainDriver: TZSQLAnywherePlainDriver;
    FSavePoints: TStrings;
    Fa_sqlany_connection: Pa_sqlany_connection;
    Fa_sqlany_interface_context: Pa_sqlany_interface_context;
    Fapi_version: Tsacapi_u32;
  private
    function DetermineASACharSet: String;
  protected
    procedure InternalCreate; override;
    procedure InternalClose; override;
    procedure ExecuteImmediat(const SQL: RawByteString; LoggingCategory: TZLoggingCategory); override;
  public
    function Get_a_sqlany_connection: Pa_sqlany_connection;
    procedure HandleError(LogginCategory: TZLoggingCategory;
      const Msg: RawByteString; const ImmediatelyReleasable: IImmediatelyReleasable);
    function GetPlainDriver: TZSQLAnywherePlainDriver;
    function Get_api_version: Tsacapi_u32;
  public
    destructor Destroy; override;

    function CreateStatementWithParams(Info: TStrings): IZStatement;
    function PrepareCallWithParams(const Name: String; Info: TStrings):
      IZCallableStatement;
    function PrepareStatementWithParams(const SQL: string; Info: TStrings):
      IZPreparedStatement;

    procedure Commit;
    procedure Rollback;
    procedure SetAutoCommit(Value: Boolean); override;
    procedure SetTransactionIsolation(Level: TZTransactIsolationLevel); override;
    function StartTransaction: Integer;

    procedure Open; override;

    function AbortOperation: Integer; override;
    function GetServerProvider: TZServerProvider; override;
  end;

{$ENDIF ZEOS_DISABLE_ASA}
implementation
{$IFNDEF ZEOS_DISABLE_ASA}

uses ZDbcASAMetadata, ZSybaseAnalyser, ZSybaseToken, ZDbcSQLAnywhereStatement,
  ZDbcProperties, ZFastCode, ZSysUtils, ZMessages, ZEncoding, ZClasses;

var
  ConParams: array of array of String;
{ TZSQLAnywhereDriver }

{**
  Attempts to make a database connection to the given URL.
  The driver should return "null" if it realizes it is the wrong kind
  of driver to connect to the given URL.  This will be common, as when
  the JDBC driver manager is asked to connect to a given URL it passes
  the URL to each loaded driver in turn.

  <P>The driver should raise a SQLException if it is the right
  driver to connect to the given URL, but has trouble connecting to
  the database.

  <P>The java.util.Properties argument can be used to passed arbitrary
  string tag/value pairs as connection arguments.
  Normally at least "user" and "password" properties should be
  included in the Properties.

  @param url the URL of the database to which to connect
  @param info a list of arbitrary string tag/value pairs as
    connection arguments. Normally at least a "user" and
    "password" property should be included.
  @return a <code>Connection</code> object that represents a
    connection to the URL
}
function TZSQLAnywhereDriver.Connect(const Url: TZURL): IZConnection;
begin
  Result := TZSQLAnywhereConnection.Create(Url);
end;

{**
  Constructs this object with default properties.
}
constructor TZSQLAnywhereDriver.Create;
begin
  inherited Create;
  AddSupportedProtocol(AddPlainDriverToCache(TZSQLAnywherePlainDriver.Create));
end;

{**
  Creates a statement analyser object.
  @returns a statement analyser object.
}
function TZSQLAnywhereDriver.GetStatementAnalyser: IZStatementAnalyser;
begin
  Result := TZSybaseStatementAnalyser.Create; { thread save! Allways return a new Analyser! }
end;

{**
  Gets a SQL syntax tokenizer.
  @returns a SQL syntax tokenizer object.
}
function TZSQLAnywhereDriver.GetTokenizer: IZTokenizer;
begin
  Result := TZSybaseTokenizer.Create; { thread save! Allways return a new Tokenizer! }
end;

{ TZSQLAnywhereConnection }

{**
  Attempts to kill a long-running operation on the database server
  side
}
function TZSQLAnywhereConnection.AbortOperation: Integer;
begin
  Result := 1;
  if Closed then
    Exit;
  FPlainDriver.sqlany_cancel(Fa_sqlany_connection);
end;

{**
  check the errorbuffer, creates the exception and frees last error in client
  interface, raises the error. So this method should be called only if an error
  is expected
}
procedure TZSQLAnywhereConnection.HandleError(
  LogginCategory: TZLoggingCategory; const Msg: RawByteString;
  const ImmediatelyReleasable: IImmediatelyReleasable);
var err_len, st_len: Tsize_t;
  ErrBuf: RawByteString;
  State, ErrMsg: String;
  ErrCode: Tsacapi_i32;
  StateBuf: array[0..5] of Byte;
  Exception: EZSQLException;
begin
  if Assigned(FPLainDriver.sqlany_error_length)
  then err_len := FPLainDriver.sqlany_error_length(Fa_sqlany_connection)
  else err_len := 1025;
  Assert(err_len > 0, 'wrong call to HandleError');
  ErrBuf := '';
  SetLength(ErrBuf, err_len -1);
  ErrCode := FPLainDriver.sqlany_error(Fa_sqlany_connection, Pointer(ErrBuf), err_len);
  if not Assigned(FPLainDriver.sqlany_error_length)
  then err_len := ZFastCode.StrLen(Pointer(ErrBuf))
  else Dec(err_len);
  SetLength(ErrBuf, err_len);

  if DriverManager.HasLoggingListener then
    DriverManager.LogError(LogginCategory, 'sqlany', Msg, ErrCode, ErrBuf);

  st_len := FPLainDriver.sqlany_sqlstate(Fa_sqlany_connection, @StateBuf[0], SizeOf(StateBuf));
  Dec(st_len);
  {$IFDEF UNICODE}
  State := USASCII7ToUnicodeString(@StateBuf[0], st_Len);
  ErrMsg := PRawToUnicode(Pointer(ErrBuf), err_Len, ImmediatelyReleasable.GetConSettings.ClientCodePage.CP);
  {$ELSE}
  {$IFDEF FPC} State := ''; {$ENDIF}
  System.SetString(State, PAnsiChar(@StateBuf[0]), st_Len);
  ErrMsg := ErrBuf + ';
  {$ENDIF}
  ErrMsg := ErrMsg + 'The SQL: ';
  {$IFDEF UNICODE}
  ErrMsg := ErrMsg + ZRawToUnicode(Msg, ImmediatelyReleasable.GetConSettings.ClientCodePage.CP);
  {$ELSE}
  ErrMsg := ErrMsg + Msg;
  {$ENDIF}

  if Assigned(FplainDriver.sqlany_clear_error) then
    FplainDriver.sqlany_clear_error(Fa_sqlany_connection);
  if ErrCode > 0 then //that's a Warning
  else begin
    Exception := EZSQLException.CreateWithCodeAndStatus(ErrCode, State, ErrMsg);
    raise Exception;
  end;
end;

const
  cCommit: RawByteString = 'TRANSACTION COMMIT';
  cRollback: RawByteString = 'TRANSACTION ROLLBACK';
{**
  Makes all changes made since the previous
  commit/rollback permanent and releases any database locks
  currently held by the Connection. This method should be
  used only when auto-commit mode has been disabled.
  @see #setAutoCommit
}
procedure TZSQLAnywhereConnection.Commit;
var S: RawByteString;
begin
  if Closed then
    raise EZSQLException.Create(SConnectionIsNotOpened);
  if AutoCommit then
    raise EZSQLException.Create(SCannotUseCommit);
  if FSavePoints.Count > 0 then begin
    S := 'RELEASE SAVEPOINT '+{$IFDEF UNICODE}UnicodeStringToAscii7{$ENDIF}(FSavePoints[FSavePoints.Count-1]);
    ExecuteImmediat(S, lcTransaction);
    FSavePoints.Delete(FSavePoints.Count-1);
  end else begin
    if FPlainDriver.sqlany_commit(Fa_sqlany_connection) <> 1 then
      HandleError(lcTransaction, cCommit, Self);
    DriverManager.LogMessage(lcTransaction,
      ConSettings^.Protocol, cCommit);
    AutoCommit := True;
    if FRestartTransaction then
      StartTransaction;
  end;
end;

{**
  Creates a <code>Statement</code> object for sending
  SQL statements to the database.
  SQL statements without parameters are normally
  executed using Statement objects. If the same SQL statement
  is executed many times, it is more efficient to use a
  <code>PreparedStatement</code> object.
  <P>
  Result sets created using the returned <code>Statement</code>
  object will by default have forward-only type and read-only concurrency.

  @param Info a statement parameters.
  @return a new Statement object
}
function TZSQLAnywhereConnection.CreateStatementWithParams(
  Info: TStrings): IZStatement;
begin
  if Closed then
    Open;
  Result := TZSQLAnywhereStatement.Create(Self, Info);
end;

destructor TZSQLAnywhereConnection.Destroy;
begin
  inherited;
  FSavePoints.Free;
end;

function TZSQLAnywhereConnection.DetermineASACharSet: String;
var
  Stmt: IZStatement;
  RS: IZResultSet;
begin
  Stmt := CreateStatementWithParams(Info);
  RS := Stmt.ExecuteQuery('SELECT DB_PROPERTY(''CharSet'')');
  if RS.Next then
    Result := RS.GetString(FirstDbcIndex)
  else
    Result := '';
  RS := nil;
  Stmt.Close;
  Stmt := nil;
end;

procedure TZSQLAnywhereConnection.ExecuteImmediat(const SQL: RawByteString;
  LoggingCategory: TZLoggingCategory);
begin
  if FPlainDriver.sqlany_execute_immediate(Fa_sqlany_connection, Pointer(SQL)) <> 0 then
    HandleError(lcExecute, SQL, Self);
  DriverManager.LogMessage(LoggingCategory, ConSettings^.Protocol, SQL);
end;

function TZSQLAnywhereConnection.GetPlainDriver: TZSQLAnywherePlainDriver;
begin
  Result := FPlainDriver;
end;

function TZSQLAnywhereConnection.GetServerProvider: TZServerProvider;
begin
  Result := spASA;
end;

function TZSQLAnywhereConnection.Get_api_version: Tsacapi_u32;
begin
  Result := Fapi_version;
end;

function TZSQLAnywhereConnection.Get_a_sqlany_connection: Pa_sqlany_connection;
begin
  Result := Fa_sqlany_connection;
end;

procedure TZSQLAnywhereConnection.InternalClose;
begin
  if Closed then
    Exit;
  FPlainDriver.sqlany_free_connection(Fa_sqlany_connection);
  Fa_sqlany_connection := nil;
  FplainDriver.sqlany_fini_ex(Fa_sqlany_interface_context);
  Fa_sqlany_interface_context := nil;
end;

procedure TZSQLAnywhereConnection.InternalCreate;
begin
  FPlainDriver := TZSQLAnywherePlainDriver(GetIZPlainDriver.GetInstance);
  Self.FMetadata := TZASADatabaseMetadata.Create(Self, URL);
  FSavePoints := TStringList.Create;
  Fapi_version := SQLANY_API_VERSION_5;
end;

procedure TZSQLAnywhereConnection.Open;
var R, ConStr: RawByteString;
  S: String;
  SQLStringWriter: TZRawSQLStringWriter;
  I, J: Integer;
  Max_api_version: Tsacapi_u32;
  procedure AddToInfoIfNotExists(const ValueName, Value: String);
  var S: String;
  begin
    if Value = '' then Exit;
    S := Info.Values[ValueName];
    if S = '' then
      Info.Values[ValueName] := Value;
  end;
label jmpInit;
begin
  if not Closed then
    Exit;
  R := '';
  S := Info.Values[ConnProps_AppName];
jmpInit:
  if S <> '' then begin
    {$IFDEF UNICODE}
    R := ZUnicodeToRaw(S, ZOsCodePage);
    {$ELSE}
    R := S;
    {$ENDIF}
    Fa_sqlany_interface_context := FplainDriver.sqlany_init_ex(Pointer(R), Fapi_version, @Max_api_version);
  end else
    Fa_sqlany_interface_context := FplainDriver.sqlany_init_ex(PEmptyAnsiString, Fapi_version, @Max_api_version);
  if (Fa_sqlany_interface_context = nil) then
    if (Max_api_version < Fapi_version) then begin//syb12 support V12 only
      Fapi_version := Max_api_version;
      goto jmpInit;
    end else raise EZSQLException.Create('Could not initialize the interface!');
  { A connection object needs to be created first }
  if Assigned(FplainDriver.sqlany_new_connection_ex)
  then Fa_sqlany_connection := FplainDriver.sqlany_new_connection_ex(Fa_sqlany_interface_context)
  else Fa_sqlany_connection := FplainDriver.sqlany_new_connection;
  { now setup a connection string }
  ConStr := '';
  Info.BeginUpdate;
  SQLStringWriter := TZRawSQLStringWriter.Create(512);
  { build a connect string }
  try
    AddToInfoIfNotExists(ConnProps_UID, URL.UserName);
    AddToInfoIfNotExists(ConnProps_PWD, URL.Password);
    if FileExists(URL.Database)
    then AddToInfoIfNotExists(ConnProps_DBF,  URL.Database)
    else AddToInfoIfNotExists(ConnProps_DBN,  URL.Database);
    AddToInfoIfNotExists(ConnProps_Host, URL.HostName);
    for i := low(ConParams) to high(ConParams) do
      for J := 0 to high(ConParams[i]) do begin
        S := Info.Values[ConParams[i][J]];
        if S <> '' then begin
          {$IFDEF UNICODE}
          SQLStringWriter.AddAscii7UTF16Text(ConParams[i][0], ConStr);
          {$ELSE UNICODE}
          SQLStringWriter.AddText(ConParams[i][0], ConStr);
          {$ENDIF UNICODE}
          SQLStringWriter.AddChar('=', ConStr);
          {$IFDEF UNICODE}
          R := ZUnicodeToRaw(S, ZOSCodePage);
          SQLStringWriter.AddText(R, ConStr);
          {$ELSE}
          SQLStringWriter.AddText(S, ConStr);
          {$ENDIF}
          SQLStringWriter.AddChar(';', ConStr);
          Break;
        end;
      end;
    SQLStringWriter.Finalize(ConStr);
    if FplainDriver.sqlany_connect(Fa_sqlany_connection, Pointer(ConStr)) <> 1 then
      HandleError(lcConnect, ConStr, Self);
    inherited Open;
  finally
    Info.EndUpdate;
    FreeAndNil(SQLStringWriter);
    if Closed then begin
      FPlainDriver.sqlany_free_connection(Fa_sqlany_connection);
      Fa_sqlany_connection := nil;
      FplainDriver.sqlany_fini_ex(Fa_sqlany_interface_context);
      Fa_sqlany_interface_context := nil;
    end;
  end;
  if FClientCodePage = ''  then begin
    S := DetermineASACharSet;
    CheckCharEncoding(S);
  end;
  //ExecuteImmediat(RawByteString('SET chained=''Off'''), lcTransaction);
  if not AutoCommit
  then StartTransaction
  else ExecuteImmediat(RawByteString('SET TEMPORARY OPTION auto_commit=''On'''), lcTransaction);
end;

{**
  Creates a <code>CallableStatement</code> object for calling
  database stored procedures.
  The <code>CallableStatement</code> object provides
  methods for setting up its IN and OUT parameters, and
  methods for executing the call to a stored procedure.

  <P><B>Note:</B> This method is optimized for handling stored
  procedure call statements. Some drivers may send the call
  statement to the database when the method <code>prepareCall</code>
  is done; others
  may wait until the <code>CallableStatement</code> object
  is executed. This has no
  direct effect on users; however, it does affect which method
  throws certain SQLExceptions.

  Result sets created using the returned CallableStatement will have
  forward-only type and read-only concurrency, by default.

  @param Name a procedure or function identifier
    parameter placeholders. Typically this  statement is a JDBC
    function call escape string.
  @param Info a statement parameters.
  @return a new CallableStatement object containing the
    pre-compiled SQL statement
}
function TZSQLAnywhereConnection.PrepareCallWithParams(const Name: String;
  Info: TStrings): IZCallableStatement;
begin
  if Closed then
    Open;
  Result := TZSQLAnywhereCallableStatement.Create(Self, Name, Info);
end;

{**
  Creates a <code>PreparedStatement</code> object for sending
  parameterized SQL statements to the database.

  A SQL statement with or without IN parameters can be
  pre-compiled and stored in a PreparedStatement object. This
  object can then be used to efficiently execute this statement
  multiple times.

  <P><B>Note:</B> This method is optimized for handling
  parametric SQL statements that benefit from precompilation. If
  the driver supports precompilation,
  the method <code>prepareStatement</code> will send
  the statement to the database for precompilation. Some drivers
  may not support precompilation. In this case, the statement may
  not be sent to the database until the <code>PreparedStatement</code> is
  executed.  This has no direct effect on users; however, it does
  affect which method throws certain SQLExceptions.

  Result sets created using the returned PreparedStatement will have
  forward-only type and read-only concurrency, by default.

  @param sql a SQL statement that may contain one or more '?' IN
    parameter placeholders
  @param Info a statement parameters.
  @return a new PreparedStatement object containing the
    pre-compiled statement
}
function TZSQLAnywhereConnection.PrepareStatementWithParams(const SQL: string;
  Info: TStrings): IZPreparedStatement;
begin
  if IsClosed then
    Open;
  Result := TZSQLAnywherePreparedStatement.Create(Self, SQL, Info);
end;

{**
  Drops all changes made since the previous
  commit/rollback and releases any database locks currently held
  by this Connection. This method should be used only when auto-
  commit has been disabled.
  @see #setAutoCommit
}
procedure TZSQLAnywhereConnection.Rollback;
var S: RawByteString;
begin
  if Closed then
    raise EZSQLException.Create(SConnectionIsNotOpened);
  if AutoCommit then
    raise EZSQLException.Create(SCannotUseRollback);
  if FSavePoints.Count > 0 then begin
    S := 'ROLLBACK TO '+{$IFDEF UNICODE}UnicodeStringToAscii7{$ENDIF}(FSavePoints[FSavePoints.Count-1]);
    ExecuteImmediat(S, lcTransaction);
    FSavePoints.Delete(FSavePoints.Count-1);
  end else begin
    if FPlainDriver.sqlany_rollback(Fa_sqlany_connection) <> 1 then
      HandleError(lcTransaction, cRollback, Self);
    DriverManager.LogMessage(lcTransaction,
      ConSettings^.Protocol, cRollback);
    AutoCommit := True;
    if FRestartTransaction then
      StartTransaction;
  end;
end;

{**
  Sets this connection's auto-commit mode.
  If a connection is in auto-commit mode, then all its SQL
  statements will be executed and committed as individual
  transactions.  Otherwise, its SQL statements are grouped into
  transactions that are terminated by a call to either
  the method <code>commit</code> or the method <code>rollback</code>.
  By default, new connections are in auto-commit mode.

  The commit occurs when the statement completes or the next
  execute occurs, whichever comes first. In the case of
  statements returning a ResultSet, the statement completes when
  the last row of the ResultSet has been retrieved or the
  ResultSet has been closed. In advanced cases, a single
  statement may return multiple results as well as output
  parameter values. In these cases the commit occurs when all results and
  output parameter values have been retrieved.

  @param autoCommit true enables auto-commit; false disables auto-commit.
}
procedure TZSQLAnywhereConnection.SetAutoCommit(Value: Boolean);
begin
  if Value <> AutoCommit then begin
    FRestartTransaction := AutoCommit;
    if Closed
    then AutoCommit := Value
    else if Value then begin
      FSavePoints.Clear;
      ExecuteImmediat(RawByteString('SET AUTO_COMMIT=ON'), lcTransaction);
      AutoCommit := True;
    end else
      StartTransaction;
  end;
end;

procedure TZSQLAnywhereConnection.SetTransactionIsolation(
  Level: TZTransactIsolationLevel);
begin
  inherited;

end;

{**
   Start transaction
}
function TZSQLAnywhereConnection.StartTransaction: Integer;
var S: String;
begin
  if Closed then
    Open;
  if AutoCommit then begin
    ExecuteImmediat(RawByteString('SET TEMPORARY OPTION auto_commit=''Off'''), lcTransaction);
    AutoCommit := False;
    Result := 1;
  end else begin
    S := 'SP'+ZFastCode.IntToStr(NativeUint(Self))+'_'+ZFastCode.IntToStr(FSavePoints.Count);
    ExecuteImmediat('SAVEPOINT '+{$IFDEF UNICODE}UnicodeStringToAscii7{$ENDIF}(S), lcTransaction);
    Result := FSavePoints.Add(S) +2;
  end;
end;

var SQLAynwhereDriver: IZDriver;

procedure addParams(Index: Integer; const Values: array of String);
var I: Integer;
begin
  SetLength(ConParams[Index], Length(Values));
  for i := low(Values) to high(Values) do
    ConParams[Index][i] := Values[i];
end;

initialization
  SQLAynwhereDriver := TZSQLAnywhereDriver.Create;
  DriverManager.RegisterDriver(SQLAynwhereDriver);

  SetLength(ConParams, 41);
  addParams(0,  [ConnProps_APP, ConnProps_AppInfo]);
  addParams(1,  [ConnProps_ASTART, ConnProps_AutoStart]);
  addParams(2,  [ConnProps_ASTOP, ConnProps_AutoStop]);
  addParams(3,  [ConnProps_CS, ConnProps_CharSet, ConnProps_CodePage]);
  addParams(4,  [ConnProps_CBSIZE, ConnProps_CommBufferSize]);
  addParams(5,  [ConnProps_LINKS, ConnProps_CommLinks]);
  addParams(6,  [ConnProps_COMP, ConnProps_Compress]);
  addParams(7,  [ConnProps_COMPTH, ConnProps_CompressionThreshold]);
  addParams(8,  [ConnProps_CON, ConnProps_ConnectionName]);
  addParams(9,  [ConnProps_CPOOL, ConnProps_ConnectionPool]);
  addParams(9,  [ConnProps_DBF, ConnProps_DatabaseFile]);
  addParams(10, [ConnProps_DBKEY, ConnProps_DatabaseKey]);
  addParams(11, [ConnProps_DBN, ConnProps_DatabaseName]);
  addParams(12, [ConnProps_DBS, ConnProps_DatabaseSwitches]);
  addParams(13, [ConnProps_DSN, ConnProps_DataSourceName]);
  addParams(14, [ConnProps_DMRF, ConnProps_DisableMultiRowFetch]);
  addParams(15, [ConnProps_Elevate]);
  addParams(16, [ConnProps_ENP, ConnProps_EncryptedPassword]);
  addParams(17, [ConnProps_ENC, ConnProps_Encryption]);
  addParams(18, [ConnProps_ENG, ConnProps_EngineName]);
  addParams(19, [ConnProps_FILEDSN, ConnProps_FileDataSourceName]);
  addParams(20, [ConnProps_FORCE, ConnProps_ForceStart]);
  addParams(21, [ConnProps_Host]);
  addParams(22, [ConnProps_Idle]);
  addParams(23, [ConnProps_INT, ConnProps_Integrated]);
  addParams(24, [ConnProps_KRB, ConnProps_Kerberos]);
  addParams(25, [ConnProps_LANG, ConnProps_Language]);
  addParams(26, [ConnProps_LCLOSE, ConnProps_LazyClose]);
  addParams(27, [ConnProps_LTO, ConnProps_LivenessTimeout]);
  addParams(28, [ConnProps_LOG, ConnProps_LogFile]);
  addParams(29, [ConnProps_NEWPWD, ConnProps_NewPassword]);
  addParams(30, [ConnProps_MatView]);
  addParams(31, [ConnProps_UID, ConnProps_Password]);
  addParams(32, [ConnProps_NODE, ConnProps_NodeType]);
  addParams(33, [ConnProps_PWD, ConnProps_Password]);
  addParams(34, [ConnProps_PBUF, ConnProps_PrefetchBuffer]);
  addParams(35, [ConnProps_PrefetchOnOpen]);
  addParams(36, [ConnProps_PROWS, ConnProps_PrefetchRows]);
  addParams(37, [ConnProps_RetryConnTO, ConnProps_RetryConnectionTimeout]);
  addParams(38, [ConnProps_Server, ConnProps_ServerName]);
  addParams(39, [ConnProps_START, ConnProps_StartLine]);
  addParams(40, [ConnProps_UNC, ConnProps_Unconditional]);
finalization
  if Assigned(DriverManager) then
    DriverManager.DeregisterDriver(SQLAynwhereDriver);
  SQLAynwhereDriver := nil;
{$ENDIF ZEOS_DISABLE_ASA}
end.