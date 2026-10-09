codeunit 52108 "MBT Http Client Helper"
{
    /// <summary>Voert een POST-request uit met JSON-body en retourneert de response als tekst.</summary>
    procedure PostJson(Url: Text; RequestBody: Text; AuthorizationHeader: Text; var ResponseBody: Text; var ErrorText: Text): Boolean
    begin
        exit(PostJson(Url, RequestBody, AuthorizationHeaderNameTok, AuthorizationHeader, ResponseBody, ErrorText));
    end;

    /// <summary>Voert een POST-request uit met JSON-body en een custom auth-headernaam (bv. "Token" i.p.v. "Authorization").</summary>
    procedure PostJson(Url: Text; RequestBody: Text; HeaderName: Text; HeaderValue: Text; var ResponseBody: Text; var ErrorText: Text): Boolean
    begin
        exit(SendRequest('POST', Url, RequestBody, HeaderName, HeaderValue, ResponseBody, ErrorText));
    end;

    /// <summary>Voert een POST-request uit met JSON-body, een custom auth-header en extra headers (bv. Accept/Accept-Language).</summary>
    procedure PostJson(Url: Text; RequestBody: Text; HeaderName: Text; HeaderValue: Text; AdditionalHeaders: Dictionary of [Text, Text]; var ResponseBody: Text; var ErrorText: Text): Boolean
    begin
        exit(SendRequest('POST', Url, RequestBody, HeaderName, HeaderValue, AdditionalHeaders, ResponseBody, ErrorText));
    end;

    /// <summary>Voert een PUT-request uit met JSON-body en retourneert de response als tekst.</summary>
    procedure PutJson(Url: Text; RequestBody: Text; AuthorizationHeader: Text; var ResponseBody: Text; var ErrorText: Text): Boolean
    begin
        exit(PutJson(Url, RequestBody, AuthorizationHeaderNameTok, AuthorizationHeader, ResponseBody, ErrorText));
    end;

    /// <summary>Voert een PUT-request uit met JSON-body en een custom auth-headernaam (bv. "Token" i.p.v. "Authorization").</summary>
    procedure PutJson(Url: Text; RequestBody: Text; HeaderName: Text; HeaderValue: Text; var ResponseBody: Text; var ErrorText: Text): Boolean
    begin
        exit(SendRequest('PUT', Url, RequestBody, HeaderName, HeaderValue, ResponseBody, ErrorText));
    end;

    /// <summary>Voert een PUT-request uit met JSON-body, een custom auth-header en extra headers (bv. Accept/Accept-Language).</summary>
    procedure PutJson(Url: Text; RequestBody: Text; HeaderName: Text; HeaderValue: Text; AdditionalHeaders: Dictionary of [Text, Text]; var ResponseBody: Text; var ErrorText: Text): Boolean
    begin
        exit(SendRequest('PUT', Url, RequestBody, HeaderName, HeaderValue, AdditionalHeaders, ResponseBody, ErrorText));
    end;

    /// <summary>Voert een GET-request uit en retourneert de response als tekst.</summary>
    procedure GetJson(Url: Text; AuthorizationHeader: Text; var ResponseBody: Text; var ErrorText: Text): Boolean
    begin
        exit(SendRequest('GET', Url, '', AuthorizationHeaderNameTok, AuthorizationHeader, ResponseBody, ErrorText));
    end;

    /// <summary>Voert een GET-request uit met een custom auth-header en extra headers (bv. Accept) en retourneert de response als tekst.</summary>
    procedure GetJson(Url: Text; HeaderName: Text; HeaderValue: Text; AdditionalHeaders: Dictionary of [Text, Text]; var ResponseBody: Text; var ErrorText: Text): Boolean
    begin
        exit(SendRequest('GET', Url, '', HeaderName, HeaderValue, AdditionalHeaders, ResponseBody, ErrorText));
    end;

    /// <summary>Voert een GET-request uit en retourneert de response als binair bestand (bv. een PDF-label).</summary>
    procedure GetForBinary(Url: Text; HeaderName: Text; HeaderValue: Text; AdditionalHeaders: Dictionary of [Text, Text]; var ResponseBlob: Codeunit "Temp Blob"; var ErrorText: Text): Boolean
    var
        ResponseBody: Text;
    begin
        exit(SendRequest('GET', Url, '', HeaderName, HeaderValue, AdditionalHeaders, true, ResponseBody, ResponseBlob, ErrorText));
    end;

    /// <summary>Voert een POST-request uit met JSON-body en retourneert de response als binair bestand (bv. een PDF-label).</summary>
    procedure PostJsonForBinary(Url: Text; RequestBody: Text; HeaderName: Text; HeaderValue: Text; AdditionalHeaders: Dictionary of [Text, Text]; var ResponseBlob: Codeunit "Temp Blob"; var ErrorText: Text): Boolean
    var
        ResponseBody: Text;
    begin
        exit(SendRequest('POST', Url, RequestBody, HeaderName, HeaderValue, AdditionalHeaders, true, ResponseBody, ResponseBlob, ErrorText));
    end;

    /// <summary>Generieke HTTP-aanroep met retry-met-backoff bij HTTP 429/5xx (FO §7.3 rate limiting).</summary>
    local procedure SendRequest(Method: Text; Url: Text; RequestBody: Text; HeaderName: Text; HeaderValue: Text; var ResponseBody: Text; var ErrorText: Text): Boolean
    var
        NoAdditionalHeaders: Dictionary of [Text, Text];
    begin
        exit(SendRequest(Method, Url, RequestBody, HeaderName, HeaderValue, NoAdditionalHeaders, ResponseBody, ErrorText));
    end;

    /// <summary>Generieke HTTP-aanroep met retry-met-backoff bij HTTP 429/5xx (FO §7.3 rate limiting) en optionele extra headers.</summary>
    local procedure SendRequest(Method: Text; Url: Text; RequestBody: Text; HeaderName: Text; HeaderValue: Text; AdditionalHeaders: Dictionary of [Text, Text]; var ResponseBody: Text; var ErrorText: Text): Boolean
    var
        UnusedBlob: Codeunit "Temp Blob";
    begin
        exit(SendRequest(Method, Url, RequestBody, HeaderName, HeaderValue, AdditionalHeaders, false, ResponseBody, UnusedBlob, ErrorText));
    end;

    /// <summary>Kernprocedure; bij BinaryResponse wordt een geslaagde respons als bytes in ResponseBlob gezet (foutresponsen blijven tekst).</summary>
    local procedure SendRequest(Method: Text; Url: Text; RequestBody: Text; HeaderName: Text; HeaderValue: Text; AdditionalHeaders: Dictionary of [Text, Text]; BinaryResponse: Boolean; var ResponseBody: Text; var ResponseBlob: Codeunit "Temp Blob"; var ErrorText: Text): Boolean
    var
        HttpClient: HttpClient;
        HttpRequestMessage: HttpRequestMessage;
        HttpResponseMessage: HttpResponseMessage;
        HttpContent: HttpContent;
        ResponseContent: HttpContent;
        HttpContentHeaders: HttpHeaders;
        HttpRequestHeaders: HttpHeaders;
        RetryCount: Integer;
        StatusCode: Integer;
        MaxRetries: Integer;
        HeaderKey: Text;
        ResponseInStream: InStream;
        ResponseOutStream: OutStream;
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

            HttpRequestMessage.GetHeaders(HttpRequestHeaders);
            if HeaderValue <> '' then begin
                if HttpRequestHeaders.Contains(HeaderName) then
                    HttpRequestHeaders.Remove(HeaderName);
                HttpRequestHeaders.Add(HeaderName, HeaderValue);
            end;
            foreach HeaderKey in AdditionalHeaders.Keys() do begin
                if HttpRequestHeaders.Contains(HeaderKey) then
                    HttpRequestHeaders.Remove(HeaderKey);
                HttpRequestHeaders.Add(HeaderKey, AdditionalHeaders.Get(HeaderKey));
            end;

            if not HttpClient.Send(HttpRequestMessage, HttpResponseMessage) then begin
                ErrorText := StrSubstNo(CommunicationErr, GetLastErrorText());
                exit(false);
            end;

            StatusCode := HttpResponseMessage.HttpStatusCode();
            if BinaryResponse and HttpResponseMessage.IsSuccessStatusCode() then begin
                // Content in een eigen variabele houden zodat de InStream geldig blijft tot CopyStream klaar is.
                ResponseContent := HttpResponseMessage.Content();
                ResponseContent.ReadAs(ResponseInStream);
                Clear(ResponseBlob);
                ResponseBlob.CreateOutStream(ResponseOutStream);
                CopyStream(ResponseOutStream, ResponseInStream);
                if ResponseBlob.Length() > 0 then
                    exit(true);

                ErrorText := StrSubstNo(EmptyResponseErr, StatusCode, GetContentType(ResponseContent));
                exit(false);
            end;
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

    local procedure GetContentType(var ResponseContent: HttpContent): Text
    var
        ResponseHeaders: HttpHeaders;
        Values: array[10] of Text;
    begin
        ResponseContent.GetHeaders(ResponseHeaders);
        if ResponseHeaders.GetValues('Content-Type', Values) then
            exit(Values[1]);
        exit('-');
    end;

    var
        AuthorizationHeaderNameTok: Label 'Authorization', Locked = true;
        CommunicationErr: Label 'Kon geen verbinding maken met de externe dienst: %1';
        HttpStatusErr: Label 'De externe dienst gaf statuscode %1 terug: %2';
        EmptyResponseErr: Label 'De externe dienst gaf statuscode %1 terug, maar de respons bevat geen gegevens (content-type: %2).';
}
