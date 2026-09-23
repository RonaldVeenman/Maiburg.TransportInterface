codeunit 52105 "MBT Claassen Connector" implements "MBT ITransportConnector"
{
    // Claassen Transport — bestandkoppeling via Azure Blob Storage (Bouwplan §7.3): uitgaand
    // wordt een XML-bestand per exportactie klaargezet in de "outbound"-map van de container,
    // inkomend wordt de "inbound"-map periodiek gepolld op terugkoppelbestanden (tracking &
    // trace). Het exacte XML-schema van Claassen is nog niet definitief vastgesteld (open punt
    // #5); onderstaande structuur is een werkbare eerste opzet die eenvoudig aan te passen is.

    procedure CreateShipment(var WhseShptHeader: Record "Warehouse Shipment Header"; var ResultText: Text; var TrackingNo: Text): Boolean
    begin
        // Claassen is een bestandconnector; individuele zendingen worden niet per stuk
        // aangeboden. Zie ExportFile.
        exit(false);
    end;

    procedure GetLabel(var WhseShptHeader: Record "Warehouse Shipment Header"; var TempBlob: Codeunit "Temp Blob"): Boolean
    begin
        // Claassen levert geen label via deze koppeling.
        exit(false);
    end;

    procedure GetTracking(var WhseShptHeader: Record "Warehouse Shipment Header"; var TrackingNo: Text; var StatusText: Text): Boolean
    begin
        // Track & trace komt via ProcessInboundFeedback (terugkoppelbestand), niet realtime.
        exit(false);
    end;

    procedure ExportFile(var TempTransportExportBuffer: Record "MBT Transport Export Buffer" temporary): Boolean
    var
        ContainerSasUrl: Text;
        BlobName: Text;
        XmlContent: Text;
        ErrorText: Text;
        ExportDateTime: DateTime;
        UploadOk: Boolean;
    begin
        if not TransportCredMgt.GetSecret(ConnectorCodeTok, 'ContainerSasUrl', ContainerSasUrl) or (ContainerSasUrl = '') then begin
            SetAllLinesError(TempTransportExportBuffer, CredentialsMissingErr);
            exit(false);
        end;

        XmlContent := BuildExportXml(TempTransportExportBuffer);
        BlobName := OutboundFolderTok + ConnectorCodeTok + '_' + Format(CurrentDateTime(), 0, '<Year4><Month,2><Day,2><Hours24><Minutes,2><Seconds,2>') + '.xml';
        ExportDateTime := CurrentDateTime();

        UploadOk := AzureBlobStorageMgt.UploadBlob(ContainerSasUrl, BlobName, XmlContent, ErrorText);

        if TempTransportExportBuffer.FindSet() then
            repeat
                TempTransportExportBuffer.Exported := UploadOk;
                if UploadOk then begin
                    TempTransportExportBuffer."Export Date Time" := ExportDateTime;
                    TempTransportExportBuffer."Error Text" := '';
                end else
                    TempTransportExportBuffer."Error Text" := CopyStr(ErrorText, 1, 250);
                TempTransportExportBuffer.Modify();
            until TempTransportExportBuffer.Next() = 0;

        exit(UploadOk);
    end;

    procedure ProcessInboundFeedback(): Boolean
    var
        ContainerSasUrl: Text;
        BlobNames: List of [Text];
        BlobName: Text;
        ErrorText: Text;
        AnyProcessed: Boolean;
    begin
        if not TransportCredMgt.GetSecret(ConnectorCodeTok, 'ContainerSasUrl', ContainerSasUrl) or (ContainerSasUrl = '') then
            exit(false);

        if not AzureBlobStorageMgt.ListBlobs(ContainerSasUrl, BlobNames, ErrorText) then begin
            TransportLogMgt.LogEntry(ConnectorCodeTok, '', Enum::"MBT Transport Log Direction"::Inbound, Enum::"MBT Transport Log Status"::Error, ErrorText);
            exit(false);
        end;

        foreach BlobName in BlobNames do
            if BlobName.StartsWith(InboundFolderTok) then
                if ProcessInboundBlob(ContainerSasUrl, BlobName) then
                    AnyProcessed := true;

        exit(AnyProcessed);
    end;

    local procedure ProcessInboundBlob(ContainerSasUrl: Text; BlobName: Text): Boolean
    var
        Content: Text;
        ErrorText: Text;
    begin
        if not AzureBlobStorageMgt.DownloadBlob(ContainerSasUrl, BlobName, Content, ErrorText) then begin
            TransportLogMgt.LogEntry(ConnectorCodeTok, '', Enum::"MBT Transport Log Direction"::Inbound, Enum::"MBT Transport Log Status"::Error, ErrorText);
            exit(false);
        end;

        ApplyFeedbackContent(Content);

        if not AzureBlobStorageMgt.DeleteBlob(ContainerSasUrl, BlobName, ErrorText) then
            TransportLogMgt.LogEntry(ConnectorCodeTok, '', Enum::"MBT Transport Log Direction"::Inbound, Enum::"MBT Transport Log Status"::Warning, ErrorText);

        exit(true);
    end;

    local procedure ApplyFeedbackContent(Content: Text)
    var
        WhseShptHeader: Record "Warehouse Shipment Header";
        LineParts: List of [Text];
        Line: Text;
        Lines: List of [Text];
        WhseShptNo: Code[20];
        TrackingNo: Text[50];
    begin
        // Verwacht formaat (eerste opzet, aan te passen zodra het Claassen-schema definitief
        // is): één regel per zending, puntkomma-gescheiden: <WhseShptNo>;<TrackingNo>;<Status>
        Lines := Content.Split('\r\n', '\n');
        foreach Line in Lines do begin
            if Line.Trim() = '' then
                continue;
            LineParts := Line.Split(';');
            if LineParts.Count() < 2 then
                continue;
            WhseShptNo := CopyStr(LineParts.Get(1).Trim(), 1, MaxStrLen(WhseShptNo));
            TrackingNo := CopyStr(LineParts.Get(2).Trim(), 1, MaxStrLen(TrackingNo));

            if WhseShptHeader.Get(WhseShptNo) then begin
                WhseShptHeader."MBT Tracking No." := TrackingNo;
                WhseShptHeader.Modify();
                TransportLogMgt.LogEntry(ConnectorCodeTok, WhseShptNo, Enum::"MBT Transport Log Direction"::Inbound, Enum::"MBT Transport Log Status"::Success, StrSubstNo(FeedbackAppliedMsg, TrackingNo));
            end;
        end;
    end;

    local procedure SetAllLinesError(var TempTransportExportBuffer: Record "MBT Transport Export Buffer" temporary; ErrorText: Text)
    begin
        if TempTransportExportBuffer.FindSet() then
            repeat
                TempTransportExportBuffer.Exported := false;
                TempTransportExportBuffer."Error Text" := CopyStr(ErrorText, 1, 250);
                TempTransportExportBuffer.Modify();
            until TempTransportExportBuffer.Next() = 0;
    end;

    local procedure BuildExportXml(var TempTransportExportBuffer: Record "MBT Transport Export Buffer" temporary): Text
    var
        XmlDoc: XmlDocument;
        RootElement: XmlElement;
        ShipmentElement: XmlElement;
        XmlContent: Text;
    begin
        XmlDoc := XmlDocument.Create();
        RootElement := XmlElement.Create('Shipments');
        XmlDoc.Add(RootElement);

        if TempTransportExportBuffer.FindSet() then
            repeat
                ShipmentElement := XmlElement.Create('Shipment');
                ShipmentElement.Add(XmlElement.Create('ShipmentNo', TempTransportExportBuffer."Whse. Shipment No."));
                ShipmentElement.Add(XmlElement.Create('CustomerName', TempTransportExportBuffer."Customer Name"));
                ShipmentElement.Add(XmlElement.Create('ShipmentDate', Format(TempTransportExportBuffer."Shipment Date", 0, 9)));
                ShipmentElement.Add(XmlElement.Create('TotalColli', Format(TempTransportExportBuffer."Total Qty. (Colli)", 0, 9)));
                ShipmentElement.Add(XmlElement.Create('TotalWeight', Format(TempTransportExportBuffer."Total Weight", 0, 9)));
                RootElement.Add(ShipmentElement);
            until TempTransportExportBuffer.Next() = 0;

        XmlDoc.WriteTo(XmlContent);
        exit(XmlContent);
    end;

    var
        TransportCredMgt: Codeunit "MBT Transport Cred. Mgt.";
        AzureBlobStorageMgt: Codeunit "MBT Azure Blob Storage Mgt.";
        TransportLogMgt: Codeunit "MBT Transport Log Mgt.";
        ConnectorCodeTok: Label 'CLAASSEN', Locked = true;
        OutboundFolderTok: Label 'outbound/', Locked = true;
        InboundFolderTok: Label 'inbound/', Locked = true;
        CredentialsMissingErr: Label 'Er is nog geen container-SAS-URL vastgelegd in Isolated Storage voor Claassen.';
        FeedbackAppliedMsg: Label 'Trackingnummer %1 verwerkt uit terugkoppelbestand.';
}
