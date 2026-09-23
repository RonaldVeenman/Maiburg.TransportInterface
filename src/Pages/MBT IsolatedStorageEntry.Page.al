page 52105 "MBT Isolated Storage Entry"
{
    Caption = 'Waarde Invoeren';
    PageType = StandardDialog;
    SourceTable = "MBT Transport Conn. Credent.";
    SourceTableTemporary = true;
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            group(General)
            {
                field(ConnectorCodeField; Rec."Connector Code")
                {
                    Caption = 'Connector';
                    Editable = false;
                    ToolTip = 'Geeft de transporteur-connector weer waarbij dit geheim hoort.';
                }
                field(SecretNameField; Rec."Secret Name")
                {
                    Caption = 'Naam';
                    Editable = false;
                    ToolTip = 'Geeft de naam van het geheim weer.';
                }
                field(ValueField; ValueTxt)
                {
                    Caption = 'Waarde';
                    ExtendedDatatype = Masked;
                    ToolTip = 'Voer de geheime waarde in. De waarde wordt niet zichtbaar opgeslagen en niet gelogd.';
                }
            }
        }
    }

    /// <summary>Bepaalt voor welke connector/secret-combinatie deze dialoog wordt getoond.</summary>
    procedure SetContext(ConnectorCode: Code[20]; SecretName: Code[50])
    begin
        Rec.Init();
        Rec."Connector Code" := ConnectorCode;
        Rec."Secret Name" := SecretName;
        Rec.Insert();
        CurrPage.Update(false);
    end;

    /// <summary>Geeft de ingevoerde waarde terug nadat de gebruiker op OK heeft geklikt.</summary>
    procedure GetValue(): Text
    begin
        exit(ValueTxt);
    end;

    var
        ValueTxt: Text;
}
