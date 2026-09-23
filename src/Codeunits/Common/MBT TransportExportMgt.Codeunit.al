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

        WhseShptHeader.SetRange("MBT Exported", false);
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
                TotalWeight += WhseShptLine.Weight * WhseShptLine."Qty. to Ship";
            until WhseShptLine.Next() = 0;
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

    local procedure GetLastErrorText(WhseShptNo: Code[20]): Text[250]
    var
        TransportLog: Record "MBT Transport Log";
    begin
        TransportLog.SetCurrentKey("Connector Code", "Whse. Shipment No.", "Date/Time");
        TransportLog.SetRange("Whse. Shipment No.", WhseShptNo);
        TransportLog.SetRange(Status, TransportLog.Status::Error);
        if TransportLog.FindLast() then
            exit(CopyStr(TransportLog."Message Text", 1, 250));
        exit('');
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
        if not TempTransportExportBuffer.FindSet() then
            exit;

        FirstIteration := true;
        repeat
            if FirstIteration or (TempTransportExportBuffer."Carrier Connector Code" <> PrevConnectorCode) then begin
                PrevConnectorCode := TempTransportExportBuffer."Carrier Connector Code";
                FirstIteration := false;
                if (PrevConnectorCode <> '') and ConnectorSetup.Get(PrevConnectorCode) then
                    ExportForConnector(TempTransportExportBuffer, ConnectorSetup);
            end;
        until TempTransportExportBuffer.Next() = 0;

        TempTransportExportBuffer.SetRange(Selected);
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
}
