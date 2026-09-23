table 52103 "MBT Transport Conn. Credent."
{
    Caption = 'Transport Connector Credentials';
    DataClassification = EndUserPseudonymousIdentifiers;
    LookupPageId = "MBT Transport Conn. Credent.";
    DrillDownPageId = "MBT Transport Conn. Credent.";

    fields
    {
        field(1; "Connector Code"; Code[20])
        {
            Caption = 'Connector Code';
            TableRelation = "MBT Transport Connector Setup".Code;
        }
        field(2; "Secret Name"; Code[50])
        {
            Caption = 'Secret Name';
            ToolTip = 'Logische naam van het geheim, bijvoorbeeld ApiUserId, ApiKey of ContainerSasUrl.';
        }
        field(3; "Isolated Storage Key"; Text[250])
        {
            Caption = 'Isolated Storage Key';
            Editable = false;
            ToolTip = 'Naam van de sleutel in Isolated Storage waaronder het geheim is opgeslagen. Bevat nooit de geheime waarde zelf.';
        }
        field(4; "Key Vault Secret Name"; Text[250])
        {
            Caption = 'Key Vault Secret Name';
            ToolTip = 'Naam van het secret in Azure Key Vault (alternatief voor Isolated Storage). Bevat nooit de geheime waarde zelf.';
        }
        field(5; Description; Text[100])
        {
            Caption = 'Description';
        }
        field(6; "Has Value"; Boolean)
        {
            Caption = 'Has Value';
            Editable = false;
            ToolTip = 'Geeft aan of er voor deze sleutel al een geheime waarde is vastgelegd in Isolated Storage.';
        }
    }

    keys
    {
        key(PK; "Connector Code", "Secret Name")
        {
            Clustered = true;
        }
    }

    trigger OnInsert()
    begin
        if "Isolated Storage Key" = '' then
            "Isolated Storage Key" := StrSubstNo('MBT-%1-%2', "Connector Code", "Secret Name");
    end;
}
