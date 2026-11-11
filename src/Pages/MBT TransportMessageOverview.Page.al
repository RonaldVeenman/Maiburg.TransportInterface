page 52102 "MBT Transport Export Buffer"
{
    Caption = 'Transport Export';
    PageType = List;
    SourceTable = "MBT Transport Export Buffer";
    SourceTableTemporary = true;
    UsageCategory = Tasks;
    ApplicationArea = All;
    DeleteAllowed = false;
    Editable = true;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(Selected; Rec.Selected)
                {
                    Editable = true;
                    ToolTip = 'Selecteer deze regel om te exporteren.';
                }
                field("Whse. Shipment No."; Rec."Whse. Shipment No.")
                {
                    Editable = false;
                    ToolTip = 'Geeft het nummer van de magazijnverzending weer.';
                }
                field("Customer Name"; Rec."Customer Name")
                {
                    Editable = false;
                    ToolTip = 'Geeft de naam van de klant weer.';
                }
                field("Carrier Connector Code"; Rec."Carrier Connector Code")
                {
                    Editable = false;
                    ToolTip = 'Geeft de gekozen expediteur (connector) weer.';
                }
                field("Total Qty. (Colli)"; Rec."Total Qty. (Colli)")
                {
                    Editable = false;
                    ToolTip = 'Geeft het totaal aantal colli weer.';
                }
                field("Total Weight"; Rec."Total Weight")
                {
                    Editable = false;
                    ToolTip = 'Geeft het totaalgewicht weer.';
                }
                field("Shipment Date"; Rec."Shipment Date")
                {
                    Editable = false;
                    ToolTip = 'Geeft de verzenddatum weer.';
                }
                field(Exported; Rec.Exported)
                {
                    Editable = false;
                    ToolTip = 'Geeft aan of deze regel al is geëxporteerd.';
                }
                field("Export Date Time"; Rec."Export Date Time")
                {
                    Editable = false;
                    ToolTip = 'Geeft aan wanneer deze regel is geëxporteerd.';
                }
                field("Tracking No."; Rec."Tracking No.")
                {
                    Editable = false;
                    ToolTip = 'Geeft het trackingnummer weer, indien bekend.';
                }
                field("Error Text"; Rec."Error Text")
                {
                    Editable = false;
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
                    if HasSelectedExportedLines() then
                        if not Confirm(ReExportConfirmQst) then
                            exit;

                    TransportExportMgt.Export(Rec);
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
            action(OpenWhseShipment)
            {
                Caption = 'Magazijnverzending';
                Image = Warehouse;
                ApplicationArea = All;
                ToolTip = 'Opent de magazijnverzending die aan deze regel is gekoppeld.';

                trigger OnAction()
                var
                    WhseShptHeader: Record "Warehouse Shipment Header";
                begin
                    if WhseShptHeader.Get(Rec."Whse. Shipment No.") then
                        Page.Run(Page::"Warehouse Shipment", WhseShptHeader);
                end;
            }
            action(OpenSourceDocument)
            {
                Caption = 'Brondocument';
                Image = Document;
                ApplicationArea = All;
                ToolTip = 'Opent het eerste brondocument dat aan deze magazijnverzending is gekoppeld.';

                trigger OnAction()
                var
                    WhseShptLine: Record "Warehouse Shipment Line";
                    WMSMgt: Codeunit "WMS Management";
                begin
                    WhseShptLine.SetRange("No.", Rec."Whse. Shipment No.");
                    if WhseShptLine.FindFirst() then
                        WMSMgt.ShowSourceDocCard(WhseShptLine."Source Type", WhseShptLine."Source Subtype", WhseShptLine."Source No.");
                end;
            }
            action(PrintLabel)
            {
                Caption = 'Label afdrukken';
                Image = Print;
                ApplicationArea = All;
                ToolTip = 'Haalt het verzendlabel op bij de gekoppelde transporteur-connector en biedt dit aan als PDF-download.';

                trigger OnAction()
                var
                    WhseShptHeader: Record "Warehouse Shipment Header";
                begin
                    if WhseShptHeader.Get(Rec."Whse. Shipment No.") then
                        if TransportExportMgt.PrintLabel(WhseShptHeader) then begin
                            Rec."Error Text" := '';
                            Rec.Modify();
                            CurrPage.Update(false);
                        end;
                end;
            }
        }
    }

    trigger OnOpenPage()
    begin
        TransportExportMgt.BuildBuffer(Rec, 0D, 0D);
    end;

    /// <summary>Controleert of er onder de geselecteerde regels al eerder geëxporteerde zitten.</summary>
    local procedure HasSelectedExportedLines(): Boolean
    var
        Found: Boolean;
    begin
        Rec.SetRange(Selected, true);
        Rec.SetRange(Exported, true);
        Found := not Rec.IsEmpty();
        Rec.SetRange(Exported);
        Rec.SetRange(Selected);
        exit(Found);
    end;

    var
        TransportExportMgt: Codeunit "MBT Transport Export Mgt.";
        ReExportConfirmQst: Label 'Een of meer geselecteerde regels zijn al eerder geëxporteerd. Wilt u deze opnieuw exporteren?';
}
