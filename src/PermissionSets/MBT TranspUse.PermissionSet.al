permissionset 52100 "MBT TRANSP-USE"
{
    Caption = 'Transport Koppeling - Gebruik';
    Assignable = true;
    Permissions =
        tabledata "MBT Transport Connector Setup" = R,
        tabledata "MBT Transport Export Buffer" = RIMD,
        tabledata "MBT Transport Log" = RI,
        table "MBT Transport Connector Setup" = X,
        table "MBT Transport Export Buffer" = X,
        table "MBT Transport Log" = X,
        codeunit "MBT Transport Export Mgt." = X,
        codeunit "MBT Transport Log Mgt." = X,
        codeunit "MBT Whse Shpt Lock Mgt." = X,
        page "MBT Transport Connector Setup" = X,
        page "MBT Transport Export Buffer" = X,
        page "MBT Transport Log" = X;
}
