codeunit 52109 "MBT Transport Cred. Mgt."
{
    /// <summary>
    /// Slaat een geheime waarde op in Isolated Storage en legt (zonder de waarde zelf)
    /// een verwijzing vast in MBT Transport Conn. Credentials (FO §7.11 / §8).
    /// </summary>
    procedure SetSecret(ConnectorCode: Code[20]; SecretName: Code[50]; Value: Text)
    var
        TransportConnCredentials: Record "MBT Transport Conn. Credent.";
        IsolatedStorageKey: Text;
    begin
        if not TransportConnCredentials.Get(ConnectorCode, SecretName) then begin
            TransportConnCredentials.Init();
            TransportConnCredentials."Connector Code" := ConnectorCode;
            TransportConnCredentials."Secret Name" := SecretName;
            TransportConnCredentials.Insert(true);
        end;

        IsolatedStorageKey := TransportConnCredentials."Isolated Storage Key";
        IsolatedStorage.Set(IsolatedStorageKey, Value, DataScope::Module);

        TransportConnCredentials."Has Value" := true;
        TransportConnCredentials.Modify(true);
    end;

    /// <summary>Leest een geheime waarde uit Isolated Storage. Retourneert false als deze niet bestaat.</summary>
    procedure GetSecret(ConnectorCode: Code[20]; SecretName: Code[50]; var Value: Text): Boolean
    var
        TransportConnCredentials: Record "MBT Transport Conn. Credent.";
    begin
        if not TransportConnCredentials.Get(ConnectorCode, SecretName) then
            exit(false);
        exit(IsolatedStorage.Get(TransportConnCredentials."Isolated Storage Key", DataScope::Module, Value));
    end;

    /// <summary>Verwijdert een geheime waarde, bijvoorbeeld bij het intrekken van een token.</summary>
    procedure DeleteSecret(ConnectorCode: Code[20]; SecretName: Code[50])
    var
        TransportConnCredentials: Record "MBT Transport Conn. Credent.";
    begin
        if not TransportConnCredentials.Get(ConnectorCode, SecretName) then
            exit;
        if IsolatedStorage.Contains(TransportConnCredentials."Isolated Storage Key", DataScope::Module) then
            IsolatedStorage.Delete(TransportConnCredentials."Isolated Storage Key", DataScope::Module);
        TransportConnCredentials."Has Value" := false;
        TransportConnCredentials.Modify(true);
    end;
}
