codeunit 52103 "MBT Dhl Connector" implements "MBT ITransportConnector"
{
    // DHL Parcel NL / eCommerce API — zie Bouwplan §7.1. Endpoints en velden zijn gebaseerd
    // op de publieke documentatie (developer.dhl.com / api-gw.dhlparcel.nl) zoals onderzocht
    // in het bouwplan; te bevestigen/valideren tegen de DHL-sandbox vóór productiegebruik
    // (open punten #8 en #9 uit het bouwplan).

    procedure CreateShipment(var WhseShptHeader: Record "Warehouse Shipment Header"; var ResultText: Text; var TrackingNo: Text): Boolean
    var
        ConnectorSetup: Record "MBT Transport Connector Setup";
        AccessToken: Text;
        RequestBody: Text;
        ResponseBody: Text;
        ErrorText: Text;
    begin
        if not ConnectorSetup.Get(ConnectorCodeTok) then begin
            ResultText := StrSubstNo(SetupMissingErr, ConnectorCodeTok);
            exit(false);
        end;

        if not GetAccessToken(AccessToken, ErrorText) then begin
            ResultText := ErrorText;
            exit(false);
        end;

        RequestBody := BuildShipmentRequestBody(WhseShptHeader);

        if not HttpClientHelper.PostJson(ConnectorSetup."Base URL" + ShipmentsEndpointTok, RequestBody, 'Bearer ' + AccessToken, ResponseBody, ErrorText) then begin
            ResultText := ErrorText;
            exit(false);
        end;

        if not ParseShipmentResponse(ResponseBody, TrackingNo, ResultText) then
            exit(false);

        exit(true);
    end;

    procedure GetLabel(var WhseShptHeader: Record "Warehouse Shipment Header"; var TempBlob: Codeunit "Temp Blob"): Boolean
    var
        ConnectorSetup: Record "MBT Transport Connector Setup";
        AccessToken: Text;
        ResponseBody: Text;
        ErrorText: Text;
        LabelOutStream: OutStream;
        LabelBase64: Text;
    begin
        if not ConnectorSetup.Get(ConnectorCodeTok) then
            exit(false);
        if WhseShptHeader."MBT Tracking No." = '' then
            exit(false);
        if not GetAccessToken(AccessToken, ErrorText) then
            exit(false);

        if not HttpClientHelper.GetJson(ConnectorSetup."Base URL" + LabelsEndpointTok + WhseShptHeader."MBT Tracking No.", 'Bearer ' + AccessToken, ResponseBody, ErrorText) then
            exit(false);

        if not ExtractJsonValue(ResponseBody, 'label', LabelBase64) then
            exit(false);

        TempBlob.CreateOutStream(LabelOutStream);
        LabelOutStream.WriteText(LabelBase64);
        exit(true);
    end;

    procedure GetTracking(var WhseShptHeader: Record "Warehouse Shipment Header"; var TrackingNo: Text; var StatusText: Text): Boolean
    var
        ConnectorSetup: Record "MBT Transport Connector Setup";
        AccessToken: Text;
        ResponseBody: Text;
        ErrorText: Text;
    begin
        if not ConnectorSetup.Get(ConnectorCodeTok) then
            exit(false);
        if WhseShptHeader."MBT Tracking No." = '' then
            exit(false);
        if not GetAccessToken(AccessToken, ErrorText) then
            exit(false);

        TrackingNo := WhseShptHeader."MBT Tracking No.";
        if not HttpClientHelper.GetJson(ConnectorSetup."Base URL" + TrackTraceEndpointTok + TrackingNo, 'Bearer ' + AccessToken, ResponseBody, ErrorText) then
            exit(false);

        exit(ExtractJsonValue(ResponseBody, 'status', StatusText));
    end;

    procedure ExportFile(var TempTransportExportBuffer: Record "MBT Transport Export Buffer" temporary): Boolean
    begin
        // DHL is een API-connector; bestandsexport is hier niet van toepassing.
        exit(false);
    end;

    procedure ProcessInboundFeedback(): Boolean
    begin
        // Terugkoppeling verloopt via polling (GetTracking, Job Queue) of eventueel een
        // webhook-ontvanger (Azure Function); zie Bouwplan §7.1.1, open punt #9.
        exit(false);
    end;

    /// <summary>
    /// Maakt de standaard credential-placeholders (UserId, ApiKey) aan in MBT Transport Conn.
    /// Credent. zodra de DHL-connector wordt ingericht, zodat de beheerder direct weet welke
    /// waarden nog moeten worden ingevoerd via de pagina Transport Connector Credentials.
    /// </summary>
    procedure EnsureRequiredCredentialsExist()
    begin
        EnsureCredentialExists('UserId', UserIdDescriptionTxt);
        EnsureCredentialExists('ApiKey', ApiKeyDescriptionTxt);
    end;

    local procedure EnsureCredentialExists(SecretName: Code[50]; Description: Text[100])
    var
        TransportConnCredentials: Record "MBT Transport Conn. Credent.";
    begin
        if TransportConnCredentials.Get(ConnectorCodeTok, SecretName) then
            exit;
        TransportConnCredentials.Init();
        TransportConnCredentials."Connector Code" := ConnectorCodeTok;
        TransportConnCredentials."Secret Name" := SecretName;
        TransportConnCredentials.Description := Description;
        TransportConnCredentials.Insert(true);
    end;

    local procedure BuildShipmentRequestBody(WhseShptHeader: Record "Warehouse Shipment Header"): Text
    var
        RequestJson: JsonObject;
        RequestText: Text;
    begin
        RequestJson.Add('reference', WhseShptHeader."No.");
        RequestJson.Add('shipmentDate', Format(WhseShptHeader."Shipment Date", 0, 9));
        RequestJson.WriteTo(RequestText);
        exit(RequestText);
    end;

    local procedure ParseShipmentResponse(ResponseBody: Text; var TrackingNo: Text; var ResultText: Text): Boolean
    begin
        ResultText := ResponseBody;
        if not ExtractJsonValue(ResponseBody, 'trackerCode', TrackingNo) then
            exit(ExtractJsonValue(ResponseBody, 'shipmentId', TrackingNo));
        exit(true);
    end;

    local procedure ExtractJsonValue(JsonText: Text; JsonKeyName: Text; var Value: Text): Boolean
    var
        ResponseJson: JsonObject;
        JsonToken: JsonToken;
    begin
        if not ResponseJson.ReadFrom(JsonText) then
            exit(false);
        if not ResponseJson.Get(JsonKeyName, JsonToken) then
            exit(false);
        Value := JsonToken.AsValue().AsText();
        exit(true);
    end;

    local procedure GetAccessToken(var AccessToken: Text; var ErrorText: Text): Boolean
    var
        ExpirationText: Text;
        Expiration: DateTime;
    begin
        if TransportCredMgt.GetSecret(ConnectorCodeTok, 'AccessToken', AccessToken) and (AccessToken <> '') then
            if TransportCredMgt.GetSecret(ConnectorCodeTok, 'AccessTokenExpiration', ExpirationText) then
                if Evaluate(Expiration, ExpirationText) then
                    if Expiration > (CurrentDateTime() + 60000) then
                        exit(true);

        exit(RefreshOrAuthenticate(AccessToken, ErrorText));
    end;

    local procedure RefreshOrAuthenticate(var AccessToken: Text; var ErrorText: Text): Boolean
    var
        RefreshToken: Text;
    begin
        if TransportCredMgt.GetSecret(ConnectorCodeTok, 'RefreshToken', RefreshToken) and (RefreshToken <> '') then
            if DoRefreshToken(RefreshToken, AccessToken, ErrorText) then
                exit(true);

        exit(DoAuthenticate(AccessToken, ErrorText));
    end;

    local procedure DoAuthenticate(var AccessToken: Text; var ErrorText: Text): Boolean
    var
        ConnectorSetup: Record "MBT Transport Connector Setup";
        UserId: Text;
        ApiKey: Text;
        RequestJson: JsonObject;
        RequestText: Text;
        ResponseBody: Text;
    begin
        if not ConnectorSetup.Get(ConnectorCodeTok) then begin
            ErrorText := StrSubstNo(SetupMissingErr, ConnectorCodeTok);
            exit(false);
        end;
        if not (TransportCredMgt.GetSecret(ConnectorCodeTok, 'UserId', UserId) and TransportCredMgt.GetSecret(ConnectorCodeTok, 'ApiKey', ApiKey)) then begin
            ErrorText := CredentialsMissingErr;
            exit(false);
        end;

        RequestJson.Add('userId', UserId);
        RequestJson.Add('key', ApiKey);
        RequestJson.WriteTo(RequestText);

        if not HttpClientHelper.PostJson(ConnectorSetup."Base URL" + AuthenticateEndpointTok, RequestText, '', ResponseBody, ErrorText) then
            exit(false);

        exit(StoreTokenResponse(ResponseBody, AccessToken, ErrorText));
    end;

    local procedure DoRefreshToken(RefreshToken: Text; var AccessToken: Text; var ErrorText: Text): Boolean
    var
        ConnectorSetup: Record "MBT Transport Connector Setup";
        RequestJson: JsonObject;
        RequestText: Text;
        ResponseBody: Text;
    begin
        if not ConnectorSetup.Get(ConnectorCodeTok) then
            exit(false);

        RequestJson.Add('refreshToken', RefreshToken);
        RequestJson.WriteTo(RequestText);

        if not HttpClientHelper.PostJson(ConnectorSetup."Base URL" + RefreshTokenEndpointTok, RequestText, '', ResponseBody, ErrorText) then
            exit(false);

        exit(StoreTokenResponse(ResponseBody, AccessToken, ErrorText));
    end;

    local procedure StoreTokenResponse(ResponseBody: Text; var AccessToken: Text; var ErrorText: Text): Boolean
    var
        RefreshToken: Text;
        RefreshExpirationText: Text;
    begin
        if not ExtractJsonValue(ResponseBody, 'accessToken', AccessToken) then begin
            ErrorText := StrSubstNo(TokenResponseErr, ResponseBody);
            exit(false);
        end;
        TransportCredMgt.SetSecret(ConnectorCodeTok, 'AccessToken', AccessToken);

        // De exacte vorm van accessTokenExpiration in de DHL-response is niet publiek
        // gedocumenteerd (zie open punt #8); als terugval wordt hier ~55 minuten aangehouden.
        TransportCredMgt.SetSecret(ConnectorCodeTok, 'AccessTokenExpiration', Format(CurrentDateTime() + 3300000));

        if ExtractJsonValue(ResponseBody, 'refreshToken', RefreshToken) then begin
            TransportCredMgt.SetSecret(ConnectorCodeTok, 'RefreshToken', RefreshToken);
            if ExtractJsonValue(ResponseBody, 'refreshTokenExpiration', RefreshExpirationText) then
                TransportCredMgt.SetSecret(ConnectorCodeTok, 'RefreshTokenExpiration', RefreshExpirationText);
        end;

        exit(true);
    end;

    var
        TransportCredMgt: Codeunit "MBT Transport Cred. Mgt.";
        HttpClientHelper: Codeunit "MBT Http Client Helper";
        ConnectorCodeTok: Label 'DHL', Locked = true;
        AuthenticateEndpointTok: Label '/authenticate/api-key', Locked = true;
        RefreshTokenEndpointTok: Label '/authenticate/refresh-token', Locked = true;
        ShipmentsEndpointTok: Label '/shipments', Locked = true;
        LabelsEndpointTok: Label '/labels/', Locked = true;
        TrackTraceEndpointTok: Label '/track-trace/', Locked = true;
        SetupMissingErr: Label 'De transportkoppeling %1 is niet (correct) ingericht in Transport Connector Setup.';
        CredentialsMissingErr: Label 'Er zijn nog geen DHL-credentials (UserId/ApiKey) vastgelegd in Isolated Storage.';
        TokenResponseErr: Label 'Kon geen geldig accessToken uit het DHL-authenticatie-antwoord lezen: %1';
        UserIdDescriptionTxt: Label 'DHL API-gebruikers-ID';
        ApiKeyDescriptionTxt: Label 'DHL API-sleutel';
}
