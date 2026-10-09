table 52100 "MBT Transport Connector Setup"
{
    Caption = 'Transport Connector Setup';
    DataClassification = CustomerContent;
    LookupPageId = "MBT Transport Connector Setup";
    DrillDownPageId = "MBT Transport Connector Setup";

    fields
    {
        field(1; Code; Code[20])
        {
            Caption = 'Code';
            NotBlank = true;
        }
        field(2; Description; Text[100])
        {
            Caption = 'Description';
        }
        field(3; "Carrier No."; Code[20])
        {
            Caption = 'Carrier No.';
            TableRelation = Vendor."No.";
        }
        field(4; "Connector Type"; Enum "MBT Transport Connector Type")
        {
            Caption = 'Connector Type';
        }
        field(5; Active; Boolean)
        {
            Caption = 'Active';
        }
        field(6; "Track and Trace Supported"; Boolean)
        {
            Caption = 'Track and Trace Supported';
        }
        field(7; "Labels Supported"; Boolean)
        {
            Caption = 'Labels Supported';
        }
        field(8; "Codeunit ID"; Integer)
        {
            Caption = 'Codeunit ID';
            ToolTip = 'Informatief: ID van de connector-codeunit. De daadwerkelijke routering gebeurt via een vaste case-dispatch op Code in Transport Export Mgt.';
        }
        field(9; "Base URL"; Text[250])
        {
            Caption = 'Base URL';
            ToolTip = 'API-basis-URL (DHL/Bumbal) of blob-containerpad (Claassen/Van der Werff).';
        }
        field(10; "Update Frequency (Minutes)"; Integer)
        {
            Caption = 'Update Frequency (Minutes)';
            ToolTip = 'Voorgestelde pollingfrequentie voor statusupdates.';
            MinValue = 0;
        }
        field(11; "Account ID"; Text[50])
        {
            Caption = 'Account ID';
            ToolTip = 'Account-/klantnummer bij de transporteur (bv. DHL accountId), indien van toepassing.';
        }
    }

    keys
    {
        key(PK; Code)
        {
            Clustered = true;
        }
    }

    trigger OnInsert()
    var
        DhlConnector: Codeunit "MBT Dhl Connector";
        BumbalConnector: Codeunit "MBT Bumbal Connector";
    begin
        // Zorgt dat de benodigde credential-placeholders meteen klaarstaan.
        if Code = DhlConnectorCodeTok then
            DhlConnector.EnsureRequiredCredentialsExist();
        if Code = BumbalConnectorCodeTok then
            BumbalConnector.EnsureRequiredCredentialsExist();
    end;

    var
        DhlConnectorCodeTok: Label 'DHL', Locked = true;
        BumbalConnectorCodeTok: Label 'BUMBAL', Locked = true;
}
