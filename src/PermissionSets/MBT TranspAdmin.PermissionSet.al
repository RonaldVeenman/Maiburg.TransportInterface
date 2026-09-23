permissionset 52101 "MBT TRANSP-ADMIN"
{
    Caption = 'Transport Koppeling - Beheer';
    Assignable = true;
    IncludedPermissionSets = "MBT TRANSP-USE";
    Permissions =
        tabledata "MBT Transport Connector Setup" = RIMD,
        tabledata "MBT Transport Conn. Credent." = RIMD,
        table "MBT Transport Conn. Credent." = X,
        codeunit "MBT Transport Cred. Mgt." = X,
        codeunit "MBT Azure Blob Storage Mgt." = X,
        codeunit "MBT Http Client Helper" = X,
        page "MBT Transport Conn. Setup Card" = X,
        page "MBT Transport Conn. Credent." = X,
        page "MBT Isolated Storage Entry" = X;
}
