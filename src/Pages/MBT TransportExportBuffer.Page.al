page 52102 "MBT Transport Export Buffer"
{
    Caption = 'Transport Export';
    PageType = List;
    SourceTable = "MBT Transport Export Buffer";
    SourceTableTemporary = true;
    UsageCategory = Tasks;
    ApplicationArea = All;
    Editable = true;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(Selected; Rec.Selected)
                {
                    ToolTip = 'Selecteer deze regel om te exporteren.';
                }
                field("Whse. Shipment No."; Rec."Whse. Shipment No.")
                {
                    ToolTip = 'Geeft het nummer van de magazijnverzending weer.';
                }
                field("Customer Name"; Rec."Customer Name")
                {
                    ToolTip = 'Geeft de naam van de klant weer.';
                }
                field("Carrier Connector Code"; Rec."Carrier Connector Code")
                {
                    ToolTip = 'Geeft de gekozen expediteur (connector) weer.';
                }
                field("Total Qty. (Colli)"; Rec."Total Qty. (Colli)")
                {
                    ToolTip = 'Geeft het totaal aantal colli weer.';
                }
                field("Total Weight"; Rec."Total Weight")
                {
                    ToolTip = 'Geeft het totaalgewicht weer.';
                }
                field("Shipment Date"; Rec."Shipment Date")
                {
                    ToolTip = 'Geeft de verzenddatum weer.';
                }
                field(Exported; Rec.Exported)
                {
                    ToolTip = 'Geeft aan of deze regel al is geëxporteerd.';
                }
                field("Export Date Time"; Rec."Export Date Time")
                {
                    ToolTip = 'Geeft aan wanneer deze regel is geëxporteerd.';
                }
                field("Tracking No."; Rec."Tracking No.")
                {
                    ToolTip = 'Geeft het trackingnummer weer, indien bekend.';
                }
                field("Error Text"; Rec."Error Text")
                {
                    ToolTip = 'Geeft de laatste foutmelding weer, indien van toepassing.';
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(Export)
            {
                Caption = 'Exporteren';
                Image = Export;
                ApplicationArea = All;
                ToolTip = 'Verzendt de geselecteerde regels naar de bijbehorende transporteur-connector.';

                trigger OnAction()
                begin
                    TransportExportMgt.Export(Rec);
                    Rec.SetRange(Selected);
                    CurrPage.Update(false);
                end;
            }
            action(SelectAll)
            {
                Caption = 'Alles selecteren';
                Image = SelectEntries;
                ApplicationArea = All;
                ToolTip = 'Selecteert alle regels in de lijst.';

                trigger OnAction()
                begin
                    if Rec.FindSet() then
                        repeat
                            Rec.Selected := true;
                            Rec.Modify();
                        until Rec.Next() = 0;
                    CurrPage.Update(false);
                end;
            }
            action(Refresh)
            {
                Caption = 'Vernieuwen';
                Image = Refresh;
                ApplicationArea = All;
                ToolTip = 'Vult de lijst opnieuw met nog niet geëxporteerde, volledig gepickte magazijnverzendingen.';

                trigger OnAction()
                begin
                    TransportExportMgt.BuildBuffer(Rec, 0D, 0D);
                    CurrPage.Update(false);
                end;
            }
        }
    }

    trigger OnOpenPage()
    begin
        TransportExportMgt.BuildBuffer(Rec, 0D, 0D);
    end;

    var
        TransportExportMgt: Codeunit "MBT Transport Export Mgt.";
}
