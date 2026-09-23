codeunit 52108 "MBT Http Client Helper"
{
    /// <summary>Voert een POST-request uit met JSON-body en retourneert de response als tekst.</summary>
    procedure PostJson(Url: Text; RequestBody: Text; AuthorizationHeader: Text; var ResponseBody: Text; var ErrorText: Text): Boolean
    begin
        exit(SendRequest('POST', Url, RequestBody, AuthorizationHeader, ResponseBody, ErrorText));
    end;

    /// <summary>Voert een PUT-request uit met JSON-body en retourneert de response als tekst.</summary>
    procedure PutJson(Url: Text; RequestBody: Text; AuthorizationHeader: Text; var ResponseBody: Text; var ErrorText: Text): Boolean
    begin
        exit(SendRequest('PUT', Url, RequestBody, AuthorizationHeader, ResponseBody, ErrorText));
    end;

    /// <summary>Voert een GET-request uit en retourneert de response als tekst.</summary>
    procedure GetJson(Url: Text; AuthorizationHeader: Text; var ResponseBody: Text; var ErrorText: Text): Boolean
    begin
        exit(SendRequest('GET', Url, '', AuthorizationHeader, ResponseBody, ErrorText));
    end;

    /// <summary>Generieke HTTP-aanroep met retry-met-backoff bij HTTP 429/5xx (FO §7.3 rate limiting).</summary>
    local procedure SendRequest(Method: Text; Url: Text; RequestBody: Text; AuthorizationHeader: Text; var ResponseBody: Text; var ErrorText: Text): Boolean
    var
        HttpClient: HttpClient;
        HttpRequestMessage: HttpRequestMessage;
        HttpResponseMessage: HttpResponseMessage;
        HttpContent: HttpContent;
        HttpContentHeaders: HttpHeaders;
        HttpRequestHeaders: HttpHeaders;
        RetryCount: Integer;
        StatusCode: Integer;
        MaxRetries: Integer;
    begin
        MaxRetries := 3;
        for RetryCount := 1 to MaxRetries do begin
            Clear(HttpRequestMessage);
            HttpRequestMessage.Method(Method);
            HttpRequestMessage.SetRequestUri(Url);

            if RequestBody <> '' then begin
                HttpContent.WriteFrom(RequestBody);
                HttpContent.GetHeaders(HttpContentHeaders);
                if HttpContentHeaders.Contains('Content-Type') then
                    HttpContentHeaders.Remove('Content-Type');
                HttpContentHeaders.Add('Content-Type', 'application/json');
                HttpRequestMessage.Content(HttpContent);
            end;

            if AuthorizationHeader <> '' then begin
                HttpRequestMessage.GetHeaders(HttpRequestHeaders);
                if HttpRequestHeaders.Contains('Authorization') then
                    HttpRequestHeaders.Remove('Authorization');
                HttpRequestHeaders.Add('Authorization', AuthorizationHeader);
            end;

            if not HttpClient.Send(HttpRequestMessage, HttpResponseMessage) then begin
                ErrorText := StrSubstNo(CommunicationErr, GetLastErrorText());
                exit(false);
            end;

            StatusCode := HttpResponseMessage.HttpStatusCode();
            HttpResponseMessage.Content().ReadAs(ResponseBody);

            if HttpResponseMessage.IsSuccessStatusCode() then
                exit(true);

            ErrorText := StrSubstNo(HttpStatusErr, StatusCode, ResponseBody);
            if not ((StatusCode = 429) or (StatusCode >= 500)) then
                exit(false);

            if RetryCount < MaxRetries then
                Sleep(1000 * RetryCount);
        end;
        exit(false);
    end;

    var
        CommunicationErr: Label 'Kon geen verbinding maken met de externe dienst: %1';
        HttpStatusErr: Label 'De externe dienst gaf statuscode %1 terug: %2';
}
