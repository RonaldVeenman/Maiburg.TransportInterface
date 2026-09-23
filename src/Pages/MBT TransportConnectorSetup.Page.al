page 52100 "MBT Transport Connector Setup"
{
    Caption = 'Transporteur Connectors';
    PageType = List;
    SourceTable = "MBT Transport Connector Setup";
    UsageCategory = Lists;
    ApplicationArea = All;
    CardPageId = "MBT Transport Conn. Setup Card";

    layout
    {
        area(Content)
        {
            repeater(General)
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
}
