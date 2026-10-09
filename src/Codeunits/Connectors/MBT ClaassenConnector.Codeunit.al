codeunit 52105 "MBT Claassen Connector" implements "MBT ITransportConnector"
{
    // Claassen Transport — bestandkoppeling (Bouwplan §7.3). Uitgaand wordt vanaf nu één
    // Excel-bestand (XLSX, opmaak conform Voorbeeld_Claassen.xlsx) gemaakt en als download
    // aangeboden; de eerdere XML-export naar de "outbound"-map van Azure Blob Storage staat nog
    // in ExportFileToAzureXml. Inkomend wordt de "inbound"-map periodiek gepolld op
    // terugkoppelbestanden (tracking & trace). Het exacte XML-schema van Claassen is nog niet
    // definitief vastgesteld (open punt #5).

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

    /// <summary>
    /// Maakt één Excel-bestand (XLSX) voor alle meegegeven (geselecteerde) Claassen-regels, zet
    /// dit in de outbound-map van Azure Blob Storage en biedt het daarnaast (voorlopig) aan als
    /// download. De opmaak volgt Voorbeeld_Claassen.xlsx: regel 1 is de koptekst, daarna één
    /// regel per magazijnverzending. De regels gelden als geëxporteerd als de upload naar Blob
    /// Storage is gelukt; de download is alleen een extra kopie. De eerdere XML-export staat
    /// nog in ExportFileToAzureXml, maar wordt niet meer aangeroepen.
    /// </summary>
    procedure ExportFile(var TempTransportExportBuffer: Record "MBT Transport Export Buffer" temporary): Boolean
    var
        TempExcelBuffer: Record "Excel Buffer" temporary;
        TempBlob: Codeunit "Temp Blob";
        ExcelOutStream: OutStream;
        ExcelInStream: InStream;
        ExportDateTime: DateTime;
        FileName: Text;
        ErrorText: Text;
        UploadOk: Boolean;
    begin
        if not TempTransportExportBuffer.FindSet() then
            exit(false);

        AddExcelHeaderRow(TempExcelBuffer);
        repeat
            AddExcelDataRow(TempExcelBuffer, TempTransportExportBuffer);
        until TempTransportExportBuffer.Next() = 0;

        TempExcelBuffer.CreateNewBook(SheetNameTxt);
        TempExcelBuffer.WriteSheet(SheetNameTxt, CompanyName(), UserId());
        TempExcelBuffer.CloseBook();
        TempBlob.CreateOutStream(ExcelOutStream);
        TempExcelBuffer.SaveToStream(ExcelOutStream, true);

        ExportDateTime := CurrentDateTime();
        FileName := ConnectorCodeTok + '_' + Format(ExportDateTime, 0, '<Year4><Month,2><Day,2><Hours24><Minutes,2><Seconds,2>') + '.xlsx';

        UploadOk := UploadExcelToBlobStorage(TempBlob, OutboundFolderTok + FileName, ErrorText);

        // Download blijft voorlopig behouden, ook als de upload mislukt (handmatig versturen).
        TempBlob.CreateInStream(ExcelInStream);
        if DownloadFromStream(ExcelInStream, DownloadExcelTxt, '', ExcelFileFilterTxt, FileName) then;

        if TempTransportExportBuffer.FindSet() then
            repeat
                TempTransportExportBuffer.Exported := UploadOk;
                if UploadOk then begin
                    TempTransportExportBuffer."Export Date Time" := ExportDateTime;
                    TempTransportExportBuffer."Error Text" := '';
                end else
                    TempTransportExportBuffer."Error Text" := CopyStr(ErrorText, 1, MaxStrLen(TempTransportExportBuffer."Error Text"));
                TempTransportExportBuffer.Modify();
            until TempTransportExportBuffer.Next() = 0;

        exit(UploadOk);
    end;

    local procedure UploadExcelToBlobStorage(var TempBlob: Codeunit "Temp Blob"; BlobName: Text; var ErrorText: Text): Boolean
    var
        ContainerSasUrl: Text;
    begin
        if not TransportCredMgt.GetSecret(ConnectorCodeTok, 'ContainerSasUrl', ContainerSasUrl) or (ContainerSasUrl = '') then begin
            ErrorText := CredentialsMissingErr;
            exit(false);
        end;
        exit(AzureBlobStorageMgt.UploadBlobFromBlob(ContainerSasUrl, BlobName, ExcelContentTypeTok, TempBlob, ErrorText));
    end;

    /// <summary>Koptekst (regel 1) overgenomen uit Voorbeeld_Claassen.xlsx; kolom E heeft bewust geen kop.</summary>
    local procedure AddExcelHeaderRow(var TempExcelBuffer: Record "Excel Buffer" temporary)
    var
        Headers: List of [Text];
        Header: Text;
    begin
        Headers := ExcelHeadersTok.Split(';');
        TempExcelBuffer.NewRow();
        foreach Header in Headers do
            TempExcelBuffer.AddColumn(Header, false, '', true, false, false, '', TempExcelBuffer."Cell Type"::Text);
    end;

    /// <summary>
    /// Eén regel per magazijnverzending. Kolommen: A TR_DISTR1, B Claassen Logistics Tilburg,
    /// C klantnummer, D t/m G ship-to naam/adres/postcode/plaats, H ISO-landcode, K leverdatum
    /// (verzenddatum), L = K + 1 dag, M colli, N totaalgewicht, O KG, P 100-1.
    /// I (Levering), J, Q en R (aantal pallets) en alle overige kolommen blijven voorlopig leeg.
    /// </summary>
    local procedure AddExcelDataRow(var TempExcelBuffer: Record "Excel Buffer" temporary; TempTransportExportBuffer: Record "MBT Transport Export Buffer" temporary)
    var
        SalesHeader: Record "Sales Header";
        ShipmentDate: Date;
        ShipToName: Text;
    begin
        FindSalesHeader(TempTransportExportBuffer."Whse. Shipment No.", SalesHeader);
        ShipmentDate := TempTransportExportBuffer."Shipment Date";
        ShipToName := SalesHeader."Ship-to Name";
        if ShipToName = '' then
            ShipToName := TempTransportExportBuffer."Customer Name";

        TempExcelBuffer.NewRow();
        AddTextCell(TempExcelBuffer, DistributorCodeTok);
        AddTextCell(TempExcelBuffer, DistributorNameTok);
        AddTextCell(TempExcelBuffer, SalesHeader."Sell-to Customer No.");
        AddTextCell(TempExcelBuffer, ShipToName);
        AddTextCell(TempExcelBuffer, SalesHeader."Ship-to Address");
        AddTextCell(TempExcelBuffer, SalesHeader."Ship-to Post Code");
        AddTextCell(TempExcelBuffer, SalesHeader."Ship-to City");
        AddTextCell(TempExcelBuffer, GetIsoCountryCode(SalesHeader."Ship-to Country/Region Code"));
        AddTextCell(TempExcelBuffer, '');//FormatExcelDate(ShipmentDate));
        AddTextCell(TempExcelBuffer, '');
        AddTextCell(TempExcelBuffer, FormatExcelDate(ShipmentDate));
        if ShipmentDate <> 0D then
            AddTextCell(TempExcelBuffer, FormatExcelDate(ShipmentDate + 1))
        else
            AddTextCell(TempExcelBuffer, '');
        AddNumberCell(TempExcelBuffer, TempTransportExportBuffer."Total Qty. (Colli)");
        AddNumberCell(TempExcelBuffer, TempTransportExportBuffer."Total Weight");
        AddTextCell(TempExcelBuffer, UnitOfWeightTok);
        AddTextCell(TempExcelBuffer, RouteTok);
    end;

    local procedure AddTextCell(var TempExcelBuffer: Record "Excel Buffer" temporary; CellValue: Text)
    begin
        TempExcelBuffer.AddColumn(CellValue, false, '', false, false, false, '', TempExcelBuffer."Cell Type"::Text);
    end;

    local procedure AddNumberCell(var TempExcelBuffer: Record "Excel Buffer" temporary; CellValue: Decimal)
    begin
        TempExcelBuffer.AddColumn(CellValue, false, '', false, false, false, '0', TempExcelBuffer."Cell Type"::Number);
    end;

    /// <summary>Datum als tekst in dezelfde notatie als het voorbeeldbestand (dd.mm.jjjj).</summary>
    local procedure FormatExcelDate(DateValue: Date): Text
    begin
        if DateValue = 0D then
            exit('');
        exit(Format(DateValue, 0, '<Day,2>.<Month,2>.<Year4>'));
    end;

    /// <summary>Zoekt de verkooporder achter de magazijnverzending; SalesHeader blijft leeg als die er niet is.</summary>
    local procedure FindSalesHeader(WhseShptNo: Code[20]; var SalesHeader: Record "Sales Header")
    var
        WhseShptLine: Record "Warehouse Shipment Line";
    begin
        Clear(SalesHeader);
        WhseShptLine.SetRange("No.", WhseShptNo);
        WhseShptLine.SetRange("Source Document", WhseShptLine."Source Document"::"Sales Order");
        if WhseShptLine.FindFirst() then
            if not SalesHeader.Get(SalesHeader."Document Type"::Order, WhseShptLine."Source No.") then
                Clear(SalesHeader);
    end;

    /// <summary>ISO 3166-1 alpha-2 landcode; bij een lege landcode (eigen land) die uit de bedrijfsgegevens, anders NL.</summary>
    local procedure GetIsoCountryCode(CountryCode: Code[10]): Text
    var
        CompanyInformation: Record "Company Information";
        CountryRegion: Record "Country/Region";
    begin
        if CountryCode = '' then begin
            CompanyInformation.Get();
            CountryCode := CompanyInformation."Country/Region Code";
        end;
        if CountryCode = '' then
            exit(DefaultCountryCodeTok);
        if CountryRegion.Get(CountryCode) then
            if CountryRegion."ISO Code" <> '' then
                exit(CountryRegion."ISO Code");
        exit(CountryCode);
    end;

    /// <summary>Eerdere werkwijze: XML-bestand naar de outbound-map van Azure Blob Storage. Wordt niet meer aangeroepen door ExportFile.</summary>
    procedure ExportFileToAzureXml(var TempTransportExportBuffer: Record "MBT Transport Export Buffer" temporary): Boolean
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
        ExcelContentTypeTok: Label 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', Locked = true;
        DownloadExcelTxt: Label 'Claassen-bestand downloaden';
        ExcelFileFilterTxt: Label 'Excel-bestanden (*.xlsx)|*.xlsx', Locked = true;
        SheetNameTxt: Label 'Claassen', Locked = true;
        DistributorCodeTok: Label 'TR_DISTR1', Locked = true;
        DistributorNameTok: Label 'Claassen Logistics Tilburg', Locked = true;
        UnitOfWeightTok: Label 'KG', Locked = true;
        RouteTok: Label '100-1', Locked = true;
        DefaultCountryCodeTok: Label 'NL', Locked = true;
        ExcelHeadersTok: Label 'Crediteur;Naam (crediteur);Debiteur;Naam (debiteur);;Postcode;Plaats;Lnd;Levering;Pickdatum;Laaddatum;Lev.term.;Colli;Totaalgewicht;Eh;Route;Levering;EP;HEP;BP;HBP;Rol;Bun;Col;HPL;Pal;Ds;Rol;Bund;Opmerkingen Loods', Locked = true;
}
