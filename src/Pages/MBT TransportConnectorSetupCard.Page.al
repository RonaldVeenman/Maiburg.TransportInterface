page 52101 "MBT Transport Conn. Setup Card"
{
    Caption = 'Transporteur Connector';
    PageType = Card;
    SourceTable = "MBT Transport Connector Setup";
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            group(General)
            {
                field(Code; Rec.Code)
                {
                    ToolTip = 'Geeft de code van de transporteur-connector weer.';
                }
                field(Description; Rec.Description)
                {
                    ToolTip = 'Geeft de omschrijving van de transporteur-connector weer.';
                }
                field("Carrier No."; Rec."Carrier No.")
                {
                    ToolTip = 'Geeft de gekoppelde vervoerder (crediteur) weer.';
                }
                field("Connector Type"; Rec."Connector Type")
                {
                    ToolTip = 'Geeft aan of de koppeling via API of bestand verloopt.';
                }
                field(Active; Rec.Active)
                {
                    ToolTip = 'Geeft aan of deze connector actief is.';
                }
                field("Track and Trace Supported"; Rec."Track and Trace Supported")
                {
                    ToolTip = 'Geeft aan of track & trace wordt ondersteund door deze connector.';
                }
                field("Labels Supported"; Rec."Labels Supported")
                {
                    ToolTip = 'Geeft aan of het ophalen van verzendlabels wordt ondersteund door deze connector.';
                }
                field("Codeunit ID"; Rec."Codeunit ID")
                {
                    ToolTip = 'Geeft ter informatie het codeunit-ID van de implementatie weer.';
                }
                field("Base URL"; Rec."Base URL")
                {
                    ToolTip = 'Geeft de basis-URL van de API of bestandslocatie weer.';
                }
                field("Update Frequency (Minutes)"; Rec."Update Frequency (Minutes)")
                {
                    ToolTip = 'Geeft aan hoe vaak (in minuten) de terugkoppeling wordt opgehaald.';
                }
            }
        }
    }

    actions
    {
        area(Navigation)
        {
            action(Credentials)
            {
                Caption = 'Credentials';
                Image = EncryptionKeys;
                ApplicationArea = All;
                ToolTip = 'Beheer de credentials (secrets) van deze connector in Isolated Storage.';

                trigger OnAction()
                var
                    TransportConnCredentials: Record "MBT Transport Conn. Credent.";
                begin
                    TransportConnCredentials.SetRange("Connector Code", Rec.Code);
                    Page.RunModal(Page::"MBT Transport Conn. Credent.", TransportConnCredentials);
                end;
            }
        }
    }
}
