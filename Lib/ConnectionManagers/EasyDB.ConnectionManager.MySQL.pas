unit EasyDB.ConnectionManager.MySQL;

interface

uses
  System.SysUtils, System.Classes,
  FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Error, FireDAC.UI.Intf, FireDAC.Phys.Intf,
  FireDAC.Stan.Def, FireDAC.Stan.Pool, FireDAC.Stan.Async, FireDAC.Phys, FireDAC.VCLUI.Wait,
  Data.DB, FireDAC.Comp.Client, FireDAC.Stan.Param, FireDAC.DatS, FireDAC.DApt.Intf, FireDAC.DApt,
  FireDAC.Comp.DataSet, {=MySQL=}FireDAC.Phys.MySQL, FireDAC.Phys.MySQLDef, FireDAC.Comp.UI, {=MySQL=}

  EasyDB.ConnectionManager.Base,
  EasyDB.Core,
  EasyDB.Logger,
  EasyDB.Consts;

 type

  TMySQLConnection = class(TConnection) // Singletone
  private
    FConnection: TFDConnection;
    FMySQLDriver: TFDPhysMySQLDriverLink;
    FQuery: TFDQuery;
    FConnectionParams: TMySqlConnectionParams;
    Constructor Create;
    class var FInstance: TMySQLConnection;
  public
    class function Instance: TMySQLConnection;
    Destructor Destroy; override;

    function GetConnectionString: string; override;
    function SetConnectionParam(AConnectionParams: TMySqlConnectionParams): TMySQLConnection;
    function Connect: Boolean; override;
    function ConnectEx: TMySQLConnection;
    function IsConnected: Boolean;
    function InitializeDatabase: Boolean;
    function Logger: TLogger; override;

    function ExecuteAdHocQuery(AScript: string): Boolean; override;
    function ExecuteAdHocQueryWithTransaction(AScript: string): Boolean;
    function ExecuteScriptFile(AScriptPath: string): Boolean; override;
    function OpenAsInteger(AScript: string): Largeint;

    procedure BeginTrans;
    procedure CommitTrans;
    procedure RollBackTrans;

    property ConnectionParams: TMySqlConnectionParams read FConnectionParams;
  end;

implementation

{ TMySQLConnection }

procedure TMySQLConnection.BeginTrans;
begin
  FConnection.Transaction.StartTransaction;
end;

procedure TMySQLConnection.CommitTrans;
begin
  FConnection.Transaction.Commit;
end;

function TMySQLConnection.Connect: Boolean;
begin
  try
    FConnection.Connected := True;
    InitializeDatabase;
    Result := True;
  except on E: Exception do
    begin
      Logger.Log(atDbConnection, E.Message);
      Result := False;
    end;
  end;
end;

function TMySQLConnection.ConnectEx: TMySQLConnection;
begin
  if Connect then
    Result := FInstance
  else
    Result := nil;
end;

constructor TMySQLConnection.Create;
begin
  FConnection := TFDConnection.Create(nil);
  FMySQLDriver := TFDPhysMySQLDriverLink.Create(nil);
  FMySQLDriver.VendorHome := '.';
  FMySQLDriver.VendorLib := 'libmysql32.dll';

  FConnection.DriverName := 'MySQL';
  FConnection.LoginPrompt := False;

  FQuery := TFDQuery.Create(nil);
  FQuery.Connection := FConnection;
end;

destructor TMySQLConnection.Destroy;
begin
  FQuery.Close;
  FQuery.Free;
  FMySQLDriver.Free;

  FConnection.Close;
  FConnection.Free;
  inherited;

end;

function TMySQLConnection.ExecuteAdHocQuery(AScript: string): Boolean;
begin
  try
    FConnection.ExecSQL(AScript);
    Result := True;
  except on E: Exception do
    begin
      E.Message := ' Script: ' + AScript + #13#10 + ' Error: ' + E.Message;
      Result := False;
      raise;
    end;
  end;
end;

function TMySQLConnection.ExecuteAdHocQueryWithTransaction(AScript: string): Boolean;
begin
  try
    BeginTrans;
    FConnection.ExecSQL(AScript);
    CommitTrans;
    Result := True;
  except on E: Exception do
    begin
      RollBackTrans;
      E.Message := ' Script: ' + AScript + #13#10 + ' Error: ' + E.Message;
      Result := False;
      raise;
    end;
  end;
end;

function TMySQLConnection.ExecuteScriptFile(AScriptPath: string): Boolean;
var
  LvStreamReader: TStreamReader;
  LvLine: string;
  LvStatement: string;
begin
  if FileExists(AScriptPath) then
  begin
    Result := True;
    LvStreamReader := TStreamReader.Create(AScriptPath, TEncoding.UTF8);
    LvLine := EmptyStr;
    LvStatement := EmptyStr;

    try
      while not LvStreamReader.EndOfStream do
      begin
        LvLine := LvStreamReader.ReadLine;
        if not LvLine.Trim.ToLower.Equals('go') then
          LvStatement := LvStatement + ' ' + LvLine
        else
        begin
          if not LvStatement.Trim.IsEmpty then
          try
            ExecuteAdHocQuery(LvStatement);
          finally
            LvStatement := EmptyStr;
          end;
        end;
      end;
    finally
      LvStreamReader.Free;
    end;
    Result := True;
  end
  else
  begin
    Logger.Log(atFileExecution, 'Script file doesn''t exists.');
    Result := False;
  end;
end;

function TMySQLConnection.GetConnectionString: string;
begin
  Result := FConnection.ConnectionString;
end;

function TMySQLConnection.InitializeDatabase: Boolean;
var
  LvTbScript: string;
begin
  LvTbScript := 'CREATE TABLE IF NOT EXISTS EasyDBVersionInfo ( ' + #10
       + '  Version BIGINT NOT NULL PRIMARY KEY, ' + #10
       + '  AppliedOn DATETIME DEFAULT CURRENT_TIMESTAMP, ' + #10
       + '  Author NVARCHAR(100), ' + #10
       + '  Description NVARCHAR(4000) ' + #10
       + ');';

  try
    ExecuteAdHocQuery(LvTbScript);
//    ExecuteAdHocQuery(LvDropScript);
//    ExecuteAdHocQuery(LvSpScript);
    Result := True;
  except on E: Exception do
    begin
      Logger.Log(atInitialize, E.Message);
      Result := False;
    end;
  end;


end;

class function TMySQLConnection.Instance: TMySQLConnection;
begin
  if not Assigned(FInstance) then
    FInstance := TMySQLConnection.Create;

  Result := FInstance;
end;

function TMySQLConnection.IsConnected: Boolean;
begin
  Result := FConnection.Connected;
end;

function TMySQLConnection.Logger: TLogger;
begin
  Result := TLogger.Instance;
end;

function TMySQLConnection.OpenAsInteger(AScript: string): Largeint;
begin
  FQuery.Open(AScript);
  if FQuery.RecordCount > 0 then
    Result := FQuery.Fields[0].AsLargeInt
  else
    Result := -1;
end;

procedure TMySQLConnection.RollBackTrans;
begin
  FConnection.Transaction.Rollback;
end;

function TMySQLConnection.SetConnectionParam(AConnectionParams: TMySqlConnectionParams): TMySQLConnection;
begin
  FConnectionParams := AConnectionParams;

  with FConnection.Params, FConnectionParams do
  begin
    Clear;
    Add('DriverID=MySQL');
    Add('Server=' + Server);
    Add('Port=' + Port.ToString);
    Add('Database=' + Schema);
    Add('User_name=' + UserName);
    Add('Password=' + Pass);
    Add('LoginTimeout=' + LoginTimeout.ToString);
  end;

  Result := FInstance;
end;

end.