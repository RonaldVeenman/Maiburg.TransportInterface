codeunit 52100 "MBT Transport Export Mgt."
{
    /// <summary>
    /// Vult het tussenscherm (FO §4.4) met nog niet geëxporteerde, volledig gepickte
    /// magazijnverzendingen binnen de opgegeven periode.
    /// </summary>
    procedure BuildBuffer(var TempTransportExportBuffer: Record "MBT Transport Export Buffer" temporary; FromDate: Date; ToDate: Date)
    var
        WhseShptHeader: Record "Warehouse Shipment Header";
    begin
        TempTransportExportBuffer.Reset();
        TempTransportExportBuffer.DeleteAll();

        // Ook al geëxporteerde verzendingen tonen (zodat ze zichtbaar/terug te vinden zijn);
        // opnieuw exporteren moet daarom eerst bevestigd worden, zie action Export op de pagina.
        WhseShptHeader.SetRange("Completely Picked", true);
        if (FromDate <> 0D) or (ToDate <> 0D) then
            WhseShptHeader.SetRange("Shipment Date", FromDate, ToDate);

        if WhseShptHeader.FindSet() then
            repeat
                AddBufferLine(TempTransportExportBuffer, WhseShptHeader);
            until WhseShptHeader.Next() = 0;
    end;

    local procedure AddBufferLine(var TempTransportExportBuffer: Record "MBT Transport Export Buffer" temporary; WhseShptHeader: Record "Warehouse Shipment Header")
    begin
        TempTransportExportBuffer.Init();
        TempTransportExportBuffer."Whse. Shipment No." := WhseShptHeader."No.";
        TempTransportExportBuffer."Carrier Connector Code" := WhseShptHeader."MBT Carrier Connector Code";
        TempTransportExportBuffer."Shipment Date" := WhseShptHeader."Shipment Date";
        TempTransportExportBuffer."Tracking No." := WhseShptHeader."MBT Tracking No.";
        TempTransportExportBuffer.Exported := WhseShptHeader."MBT Exported";
        TempTransportExportBuffer."Export Date Time" := WhseShptHeader."MBT Export Date/Time";
        GetTotals(WhseShptHeader."No.", TempTransportExportBuffer."Total Qty. (Colli)", TempTransportExportBuffer."Total Weight");
        TempTransportExportBuffer."Customer Name" := GetCustomerName(WhseShptHeader."No.");
        TempTransportExportBuffer."Error Text" := GetLastErrorText(WhseShptHeader."No.");
        TempTransportExportBuffer.Insert();
    end;

    local procedure GetTotals(WhseShptNo: Code[20]; var TotalQty: Decimal; var TotalWeight: Decimal)
    var
        WhseShptLine: Record "Warehouse Shipment Line";
    begin
        TotalQty := 0;
        TotalWeight := 0;
        WhseShptLine.SetRange("No.", WhseShptNo);
        if WhseShptLine.FindSet() then
            repeat
                TotalQty += WhseShptLine."Qty. to Ship (Base)";
                // Weight is al het totaalgewicht van de regel, niet een gewicht per stuk.
                TotalWeight += WhseShptLine.Weight;
            until WhseShptLine.Next() = 0;
        TotalWeight := Round(TotalWeight, 1);
    end;

    local procedure GetCustomerName(WhseShptNo: Code[20]): Text[100]
    var
        WhseShptLine: Record "Warehouse Shipment Line";
        SalesLine: Record "Sales Line";
        SalesHeader: Record "Sales Header";
    begin
        WhseShptLine.SetRange("No.", WhseShptNo);
        if not WhseShptLine.FindFirst() then
            exit('');
        if WhseShptLine."Source Type" <> Database::"Sales Line" then
            exit('');
        if not SalesLine.Get(Enum::"Sales Document Type".FromInteger(WhseShptLine."Source Subtype"), WhseShptLine."Source No.", WhseShptLine."Source Line No.") then
            exit('');
        if not SalesHeader.Get(SalesLine."Document Type", SalesLine."Document No.") then
            exit('');
        exit(SalesHeader."Sell-to Customer Name");
    end;

    /// <summary>Geeft de laatste foutmelding van de verzending, tenzij daarna een geslaagde actie (export of label) is gelogd.</summary>
    local procedure GetLastErrorText(WhseShptNo: Code[20]): Text[250]
    var
        TransportLog: Record "MBT Transport Log";
        LastErrorDateTime: DateTime;
        ErrorText: Text[250];
    begin
        TransportLog.SetCurrentKey("Connector Code", "Whse. Shipment No.", "Date/Time");
        TransportLog.SetRange("Whse. Shipment No.", WhseShptNo);
        TransportLog.SetRange(Status, TransportLog.Status::Error);
        if not TransportLog.FindLast() then
            exit('');
        LastErrorDateTime := TransportLog."Date/Time";
        ErrorText := CopyStr(TransportLog."Message Text", 1, 250);

        TransportLog.SetRange(Status, TransportLog.Status::Success);
        TransportLog.SetFilter("Date/Time", '>%1', LastErrorDateTime);
        if not TransportLog.IsEmpty() then
            exit('');
        exit(ErrorText);
    end;

    /// <summary>
    /// Verwerkt de geselecteerde regels uit het tussenscherm, gegroepeerd per connector
    /// (FO §7.8): per regel voor API-connectors, gebundeld voor bestandconnectors.
    /// </summary>
    procedure Export(var TempTransportExportBuffer: Record "MBT Transport Export Buffer" temporary)
    var
        ConnectorSetup: Record "MBT Transport Connector Setup";
        PrevConnectorCode: Code[20];
        FirstIteration: Boolean;
    begin
        TempTransportExportBuffer.SetRange(Selected, true);
        TempTransportExportBuffer.SetCurrentKey("Carrier Connector Code");
        if TempTransportExportBuffer.FindSet() then begin
            FirstIteration := true;
            repeat
                if FirstIteration or (TempTransportExportBuffer."Carrier Connector Code" <> PrevConnectorCode) then begin
                    PrevConnectorCode := TempTransportExportBuffer."Carrier Connector Code";
                    FirstIteration := false;
                    if (PrevConnectorCode <> '') and ConnectorSetup.Get(PrevConnectorCode) then
                        ExportForConnector(TempTransportExportBuffer, ConnectorSetup);
                end;
            until TempTransportExportBuffer.Next() = 0;
        end;

        // Filter altijd terugzetten, ook als er niets geselecteerd was (voorheen bleef de pagina anders gefilterd op Selected).
        TempTransportExportBuffer.SetRange(Selected);
        TempTransportExportBuffer.SetRange("Carrier Connector Code");
        TempTransportExportBuffer.SetCurrentKey("Whse. Shipment No.");
    end;

    local procedure ExportForConnector(var TempTransportExportBuffer: Record "MBT Transport Export Buffer" temporary; ConnectorSetup: Record "MBT Transport Connector Setup")
    var
        TempConnectorLines: Record "MBT Transport Export Buffer" temporary;
    begin
        TempConnectorLines.Reset();
        TempConnectorLines.DeleteAll();

        TempTransportExportBuffer.SetRange("Carrier Connector Code", ConnectorSetup.Code);
        if TempTransportExportBuffer.FindSet() then
            repeat
                TempConnectorLines := TempTransportExportBuffer;
                TempConnectorLines.Insert();
            until TempTransportExportBuffer.Next() = 0;

        case ConnectorSetup."Connector Type" of
            ConnectorSetup."Connector Type"::API:
                ExportApiLines(TempConnectorLines, ConnectorSetup.Code);
            ConnectorSetup."Connector Type"::File:
                ExportFileLines(TempConnectorLines, ConnectorSetup.Code);
        end;

        SyncBackToBuffer(TempTransportExportBuffer, TempConnectorLines);
    end;

    local procedure ExportApiLines(var TempConnectorLines: Record "MBT Transport Export Buffer" temporary; ConnectorCode: Code[20])
    var
        WhseShptHeader: Record "Warehouse Shipment Header";
        ITransportConnector: Interface "MBT ITransportConnector";
        ResultText: Text;
        TrackingNo: Text;
    begin
        GetConnector(ConnectorCode, ITransportConnector);
        if not TempConnectorLines.FindSet() then
            exit;
        repeat
            if WhseShptHeader.Get(TempConnectorLines."Whse. Shipment No.") then
                if ITransportConnector.CreateShipment(WhseShptHeader, ResultText, TrackingNo) then begin
                    WhseShptHeader."MBT Exported" := true;
                    WhseShptHeader."MBT Export Date/Time" := CurrentDateTime();
                    WhseShptHeader."MBT Export Error" := false;
                    WhseShptHeader."MBT Tracking No." := CopyStr(TrackingNo, 1, MaxStrLen(WhseShptHeader."MBT Tracking No."));
                    WhseShptHeader.Modify();

                    TempConnectorLines.Exported := true;
                    TempConnectorLines."Export Date Time" := WhseShptHeader."MBT Export Date/Time";
                    TempConnectorLines."Tracking No." := WhseShptHeader."MBT Tracking No.";
                    TempConnectorLines."Error Text" := '';
                    TempConnectorLines.Modify();

                    TransportLogMgt.LogEntry(ConnectorCode, WhseShptHeader."No.", Enum::"MBT Transport Log Direction"::Outbound, Enum::"MBT Transport Log Status"::Success, CopyStr(ResultText, 1, 2048));
                end else begin
                    WhseShptHeader."MBT Export Error" := true;
                    WhseShptHeader.Modify();

                    TempConnectorLines."Error Text" := CopyStr(ResultText, 1, 250);
                    TempConnectorLines.Modify();

                    TransportLogMgt.LogEntry(ConnectorCode, WhseShptHeader."No.", Enum::"MBT Transport Log Direction"::Outbound, Enum::"MBT Transport Log Status"::Error, CopyStr(ResultText, 1, 2048));
                end;
        until TempConnectorLines.Next() = 0;
    end;

    local procedure ExportFileLines(var TempConnectorLines: Record "MBT Transport Export Buffer" temporary; ConnectorCode: Code[20])
    var
        WhseShptHeader: Record "Warehouse Shipment Header";
        ITransportConnector: Interface "MBT ITransportConnector";
    begin
        GetConnector(ConnectorCode, ITransportConnector);
        ITransportConnector.ExportFile(TempConnectorLines);

        if not TempConnectorLines.FindSet() then
            exit;
        repeat
            if WhseShptHeader.Get(TempConnectorLines."Whse. Shipment No.") then begin
                WhseShptHeader."MBT Exported" := TempConnectorLines.Exported;
                WhseShptHeader."MBT Export Error" := not TempConnectorLines.Exported;
                WhseShptHeader."MBT Export Date/Time" := TempConnectorLines."Export Date Time";
                WhseShptHeader."MBT Tracking No." := TempConnectorLines."Tracking No.";
                WhseShptHeader.Modify();
            end;

            if TempConnectorLines.Exported then
                TransportLogMgt.LogEntry(ConnectorCode, TempConnectorLines."Whse. Shipment No.", Enum::"MBT Transport Log Direction"::Outbound, Enum::"MBT Transport Log Status"::Success, ExportedToFileMsg)
            else
                TransportLogMgt.LogEntry(ConnectorCode, TempConnectorLines."Whse. Shipment No.", Enum::"MBT Transport Log Direction"::Outbound, Enum::"MBT Transport Log Status"::Error, CopyStr(TempConnectorLines."Error Text", 1, 2048));
        until TempConnectorLines.Next() = 0;
    end;

    /// <summary>
    /// Haalt het verzendlabel op bij de gekoppelde transporteur-connector (bv. DHL "Create
    /// labels") en biedt dit aan als PDF-download. Alleen van toepassing als de connector
    /// labels ondersteunt en de verzending al een trackingnummer heeft (FO §7.1).
    /// Geeft true terug als het label is gedownload; dan wordt ook de exportfout van de
    /// magazijnverzending gewist.
    /// </summary>
    procedure PrintLabel(var WhseShptHeader: Record "Warehouse Shipment Header"): Boolean
    var
        ConnectorSetup: Record "MBT Transport Connector Setup";
        ITransportConnector: Interface "MBT ITransportConnector";
        TempBlob: Codeunit "Temp Blob";
        LabelInStream: InStream;
        FileName: Text;
    begin
        if WhseShptHeader."MBT Carrier Connector Code" = '' then
            Error(NoConnectorSelectedErr);
        if not ConnectorSetup.Get(WhseShptHeader."MBT Carrier Connector Code") then
            Error(ConnectorSetupMissingErr, WhseShptHeader."MBT Carrier Connector Code");
        if not ConnectorSetup."Labels Supported" then
            Error(LabelsNotSupportedErr, ConnectorSetup.Code);
        if WhseShptHeader."MBT Tracking No." = '' then
            Error(NotYetExportedErr);

        GetConnector(ConnectorSetup.Code, ITransportConnector);
        if not ITransportConnector.GetLabel(WhseShptHeader, TempBlob) then begin
            TransportLogMgt.LogEntry(ConnectorSetup.Code, WhseShptHeader."No.", Enum::"MBT Transport Log Direction"::Outbound, Enum::"MBT Transport Log Status"::Error, LabelRetrievalErr);
            Error(LabelRetrievalErr);
        end;

        TempBlob.CreateInStream(LabelInStream);
        FileName := WhseShptHeader."MBT Tracking No." + '.pdf';
        if not DownloadFromStream(LabelInStream, DownloadLabelTxt, '', LabelFileFilterTxt, FileName) then
            exit(false);

        // Het label is opgehaald: een eerdere exportfout is daarmee achterhaald. Logregels blijven
        // bewaard; de laatste Success-regel zorgt dat de oude fout niet meer in het tussenscherm staat.
        if WhseShptHeader."MBT Export Error" then begin
            WhseShptHeader."MBT Export Error" := false;
            WhseShptHeader.Modify();
        end;
        TransportLogMgt.LogEntry(ConnectorSetup.Code, WhseShptHeader."No.", Enum::"MBT Transport Log Direction"::Outbound, Enum::"MBT Transport Log Status"::Success, LabelDownloadedMsg);
        exit(true);
    end;

    local procedure SyncBackToBuffer(var TempTransportExportBuffer: Record "MBT Transport Export Buffer" temporary; var TempConnectorLines: Record "MBT Transport Export Buffer" temporary)
    begin
        if not TempConnectorLines.FindSet() then
            exit;
        repeat
            if TempTransportExportBuffer.Get(TempConnectorLines."Whse. Shipment No.") then begin
                TempTransportExportBuffer.Exported := TempConnectorLines.Exported;
                TempTransportExportBuffer."Export Date Time" := TempConnectorLines."Export Date Time";
                TempTransportExportBuffer."Tracking No." := TempConnectorLines."Tracking No.";
                TempTransportExportBuffer."Error Text" := TempConnectorLines."Error Text";
                TempTransportExportBuffer.Modify();
            end;
        until TempConnectorLines.Next() = 0;
    end;

    /// <summary>
    /// Vaste case-dispatch naar de connector-implementatie op basis van Code (FO §4.2:
    /// alternatief voor dispatch via het "Codeunit ID"-veld).
    /// </summary>
    local procedure GetConnector(ConnectorCode: Code[20]; var ITransportConnector: Interface "MBT ITransportConnector")
    var
        DhlConnector: Codeunit "MBT Dhl Connector";
        BumbalConnector: Codeunit "MBT Bumbal Connector";
        ClaassenConnector: Codeunit "MBT Claassen Connector";
        VanDerWerffConnector: Codeunit "MBT VanDerWerff Connector";
    begin
        case ConnectorCode of
            'DHL':
                ITransportConnector := DhlConnector;
            'BUMBAL':
                ITransportConnector := BumbalConnector;
            'CLAASSEN':
                ITransportConnector := ClaassenConnector;
            'VDWERFF':
                ITransportConnector := VanDerWerffConnector;
            else
                Error(UnknownConnectorErr, ConnectorCode);
        end;
    end;

    var
        TransportLogMgt: Codeunit "MBT Transport Log Mgt.";
        ExportedToFileMsg: Label 'Regel opgenomen in uitgaand bestand.';
        UnknownConnectorErr: Label 'Onbekende transporteur-connector: %1';
        NoConnectorSelectedErr: Label 'Er is geen expediteur (transporteur-connector) gekoppeld aan deze magazijnverzending.';
        ConnectorSetupMissingErr: Label 'De transportkoppeling %1 is niet (correct) ingericht in Transport Connector Setup.';
        LabelsNotSupportedErr: Label 'De transporteur-connector %1 ondersteunt geen labels.';
        NotYetExportedErr: Label 'Deze magazijnverzending is nog niet (succesvol) geëxporteerd naar de transporteur; er is nog geen trackingnummer bekend.';
        LabelRetrievalErr: Label 'Kon geen verzendlabel ophalen bij de transporteur.';
        LabelDownloadedMsg: Label 'Verzendlabel gedownload.';
        DownloadLabelTxt: Label 'Verzendlabel downloaden';
        LabelFileFilterTxt: Label 'PDF-bestanden (*.pdf)|*.pdf', Locked = true;
}
