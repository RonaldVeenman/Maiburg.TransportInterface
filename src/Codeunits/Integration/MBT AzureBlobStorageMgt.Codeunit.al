codeunit 52107 "MBT Azure Blob Storage Mgt."
{
    /// <summary>
    /// Generieke bouwsteen voor het schrijven/lezen van bestanden naar/uit Azure Blob Storage.
    /// Wordt gebruikt als brug naar Claassen Transport (SFTP via Logic App/Function) en is
    /// zo generiek opgezet dat hij later hergebruikt kan worden voor Van der Werff (zie §7.3/§7.4).
    /// Authenticatie gebeurt via een SAS-token dat als onderdeel van de container-URL wordt
    /// opgeslagen in Isolated Storage (zie MBT Transport Conn. Credentials, §8).
    /// </summary>
    procedure UploadBlob(ContainerSasUrl: Text; BlobName: Text; Content: Text; var ErrorText: Text): Boolean
    var
        HttpClient: HttpClient;
        RequestMessage: HttpRequestMessage;
        ResponseMessage: HttpResponseMessage;
        BlobContent: HttpContent;
        ContentHeaders: HttpHeaders;
        RequestHeaders: HttpHeaders;
    begin
        BlobContent.WriteFrom(Content);
        BlobContent.GetHeaders(ContentHeaders);
        if ContentHeaders.Contains('Content-Type') then
            ContentHeaders.Remove('Content-Type');
        ContentHeaders.Add('Content-Type', 'application/xml');

        RequestMessage.Method('PUT');
        RequestMessage.SetRequestUri(BuildBlobUrl(ContainerSasUrl, BlobName));
        RequestMessage.Content(BlobContent);
        RequestMessage.GetHeaders(RequestHeaders);
        RequestHeaders.Add('x-ms-blob-type', 'BlockBlob');
        RequestHeaders.Add('x-ms-version', AzureStorageApiVersionTxt);

        if not HttpClient.Send(RequestMessage, ResponseMessage) then begin
            ErrorText := GetLastErrorText();
            exit(false);
        end;
        if not ResponseMessage.IsSuccessStatusCode() then begin
            ResponseMessage.Content().ReadAs(ErrorText);
            exit(false);
        end;
        exit(true);
    end;

    /// <summary>Downloadt de inhoud van één blob als tekst.</summary>
    procedure DownloadBlob(ContainerSasUrl: Text; BlobName: Text; var Content: Text; var ErrorText: Text): Boolean
    var
        HttpClient: HttpClient;
        RequestMessage: HttpRequestMessage;
        ResponseMessage: HttpResponseMessage;
        RequestHeaders: HttpHeaders;
    begin
        RequestMessage.Method('GET');
        RequestMessage.SetRequestUri(BuildBlobUrl(ContainerSasUrl, BlobName));
        RequestMessage.GetHeaders(RequestHeaders);
        RequestHeaders.Add('x-ms-version', AzureStorageApiVersionTxt);

        if not HttpClient.Send(RequestMessage, ResponseMessage) then begin
            ErrorText := GetLastErrorText();
            exit(false);
        end;
        if not ResponseMessage.IsSuccessStatusCode() then begin
            ResponseMessage.Content().ReadAs(ErrorText);
            exit(false);
        end;
        ResponseMessage.Content().ReadAs(Content);
        exit(true);
    end;

    /// <summary>Verwijdert een blob, bijvoorbeeld na verwerking van een terugkoppelbestand.</summary>
    procedure DeleteBlob(ContainerSasUrl: Text; BlobName: Text; var ErrorText: Text): Boolean
    var
        HttpClient: HttpClient;
        RequestMessage: HttpRequestMessage;
        ResponseMessage: HttpResponseMessage;
        RequestHeaders: HttpHeaders;
    begin
        RequestMessage.Method('DELETE');
        RequestMessage.SetRequestUri(BuildBlobUrl(ContainerSasUrl, BlobName));
        RequestMessage.GetHeaders(RequestHeaders);
        RequestHeaders.Add('x-ms-version', AzureStorageApiVersionTxt);

        if not HttpClient.Send(RequestMessage, ResponseMessage) then begin
            ErrorText := GetLastErrorText();
            exit(false);
        end;
        if not ResponseMessage.IsSuccessStatusCode() then begin
            ResponseMessage.Content().ReadAs(ErrorText);
            exit(false);
        end;
        exit(true);
    end;

    /// <summary>Geeft de blobnamen in de container terug (voor het vinden van terugkoppelbestanden).</summary>
    procedure ListBlobs(ContainerSasUrl: Text; var BlobNames: List of [Text]; var ErrorText: Text): Boolean
    var
        HttpClient: HttpClient;
        RequestMessage: HttpRequestMessage;
        ResponseMessage: HttpResponseMessage;
        RequestHeaders: HttpHeaders;
        ResponseText: Text;
        XmlDoc: XmlDocument;
        NameNodes: XmlNodeList;
        NameNode: XmlNode;
    begin
        RequestMessage.Method('GET');
        RequestMessage.SetRequestUri(BuildListUrl(ContainerSasUrl));
        RequestMessage.GetHeaders(RequestHeaders);
        RequestHeaders.Add('x-ms-version', AzureStorageApiVersionTxt);

        if not HttpClient.Send(RequestMessage, ResponseMessage) then begin
            ErrorText := GetLastErrorText();
            exit(false);
        end;
        if not ResponseMessage.IsSuccessStatusCode() then begin
            ResponseMessage.Content().ReadAs(ErrorText);
            exit(false);
        end;

        ResponseMessage.Content().ReadAs(ResponseText);
        if not XmlDocument.ReadFrom(ResponseText, XmlDoc) then begin
            ErrorText := InvalidListResponseErr;
            exit(false);
        end;

        if XmlDoc.SelectNodes('//Blobs/Blob/Name', NameNodes) then
            foreach NameNode in NameNodes do
                BlobNames.Add(NameNode.AsXmlElement().InnerText());

        exit(true);
    end;

    local procedure BuildBlobUrl(ContainerSasUrl: Text; BlobName: Text): Text
    var
        QueryPos: Integer;
    begin
        QueryPos := StrPos(ContainerSasUrl, '?');
        if QueryPos = 0 then
            exit(ContainerSasUrl + '/' + BlobName);
        exit(CopyStr(ContainerSasUrl, 1, QueryPos - 1) + '/' + BlobName + CopyStr(ContainerSasUrl, QueryPos));
    end;

    local procedure BuildListUrl(ContainerSasUrl: Text): Text
    var
        QueryPos: Integer;
    begin
        QueryPos := StrPos(ContainerSasUrl, '?');
        if QueryPos = 0 then
            exit(ContainerSasUrl + '?restype=container&comp=list');
        exit(CopyStr(ContainerSasUrl, 1, QueryPos) + 'restype=container&comp=list&' + CopyStr(ContainerSasUrl, QueryPos + 1));
    end;

    var
        AzureStorageApiVersionTxt: Label '2021-08-06', Locked = true;
        InvalidListResponseErr: Label 'Het antwoord van Azure Blob Storage (List Blobs) kon niet worden gelezen.';
}
