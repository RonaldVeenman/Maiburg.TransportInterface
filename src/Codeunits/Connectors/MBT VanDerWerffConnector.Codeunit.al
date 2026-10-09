codeunit 52106 "MBT VanDerWerff Connector" implements "MBT ITransportConnector"
{
    // Van der Werff — bestandkoppeling. Uitgaand wordt één XML-bestand per exportactie in de
    // "outbound"-map van Azure Blob Storage gezet (zelfde eerste opzet als de eerdere Claassen-
    // XML; het definitieve Van der Werff-schema is nog niet vastgesteld, FO-openstaand punt #4).
    // Een API-koppeling, labels, tracking en het verwerken van terugkoppelbestanden zijn nog niet
    // gebouwd (stub, zie Bouwplan §7.4); dat wordt later aangevuld of vervangen door een echte
    // implementatie (of "MBT VanDerWerff Api Connector" wanneer Van der Werff overstapt naar een API).

    procedure CreateShipment(var WhseShptHeader: Record "Warehouse Shipment Header"; var ResultText: Text; var TrackingNo: Text): Boolean
    begin
        Error(NotYetImplementedErr, WhseShptHeader."No.");
    end;

    procedure GetLabel(var WhseShptHeader: Record "Warehouse Shipment Header"; var TempBlob: Codeunit "Temp Blob"): Boolean
    begin
        Error(NotYetImplementedErr, WhseShptHeader."No.");
    end;

    procedure GetTracking(var WhseShptHeader: Record "Warehouse Shipment Header"; var TrackingNo: Text; var StatusText: Text): Boolean
    begin
        Error(NotYetImplementedErr, WhseShptHeader."No.");
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
        ExportDateTime := CurrentDateTime();
        BlobName := OutboundFolderTok + ConnectorCodeTok + '_' + Format(ExportDateTime, 0, '<Year4><Month,2><Day,2><Hours24><Minutes,2><Seconds,2>') + '.xml';

        UploadOk := AzureBlobStorageMgt.UploadBlob(ContainerSasUrl, BlobName, XmlContent, ErrorText);

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

    procedure ProcessInboundFeedback(): Boolean
    begin
        Error(NotYetImplementedGenericErr);
    end;

    local procedure SetAllLinesError(var TempTransportExportBuffer: Record "MBT Transport Export Buffer" temporary; ErrorText: Text)
    begin
        if TempTransportExportBuffer.FindSet() then
            repeat
                TempTransportExportBuffer.Exported := false;
                TempTransportExportBuffer."Error Text" := CopyStr(ErrorText, 1, MaxStrLen(TempTransportExportBuffer."Error Text"));
                TempTransportExportBuffer.Modify();
            until TempTransportExportBuffer.Next() = 0;
    end;

    /// <summary>Eerste opzet van het uitgaande XML-bestand (zelfde indeling als de Claassen-XML), één element per magazijnverzending.</summary>
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
        ConnectorCodeTok: Label 'VDWERFF', Locked = true;
        OutboundFolderTok: Label 'outbound/', Locked = true;
        CredentialsMissingErr: Label 'Er is nog geen container-SAS-URL vastgelegd in Isolated Storage voor Van der Werff.';
        NotYetImplementedErr: Label 'De koppeling met Van der Werff is nog niet ontwikkeld. Zendingnummer: %1. Neem contact op met de projectleider zodra het XML-schema van Van der Werff is vastgesteld.';
        NotYetImplementedGenericErr: Label 'De koppeling met Van der Werff is nog niet ontwikkeld. Neem contact op met de projectleider zodra het XML-schema van Van der Werff is vastgesteld.';
}
