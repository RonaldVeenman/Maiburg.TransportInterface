codeunit 52104 "MBT Bumbal Connector" implements "MBT ITransportConnector"
{
    // Bumbal (FreightLive) Activity-API — zie Bouwplan §7.2. De exacte tenant-basis-URL,
    // credentials en de volledige veldverplichtingen zijn niet publiek gedocumenteerd en
    // moeten bij Bumbal worden opgevraagd vóór productiegebruik (open punt #7). De vorm van
    // track & trace-terugkoppeling (response/polling/webhook) is eveneens nog te bevestigen
    // (open punt #3).

    procedure CreateShipment(var WhseShptHeader: Record "Warehouse Shipment Header"; var ResultText: Text; var TrackingNo: Text): Boolean
    var
        ConnectorSetup: Record "MBT Transport Connector Setup";
        AuthorizationHeader: Text;
        RequestBody: Text;
        ResponseBody: Text;
        ErrorText: Text;
    begin
        if not ConnectorSetup.Get(ConnectorCodeTok) then begin
            ResultText := StrSubstNo(SetupMissingErr, ConnectorCodeTok);
            exit(false);
        end;

        if not GetAuthorizationHeader(AuthorizationHeader, ErrorText) then begin
            ResultText := ErrorText;
            exit(false);
        end;

        RequestBody := BuildActivityRequestBody(WhseShptHeader);

        if not HttpClientHelper.PostJson(ConnectorSetup."Base URL" + ActivitySetEndpointTok, RequestBody, AuthorizationHeader, ResponseBody, ErrorText) then begin
            ResultText := ErrorText;
            exit(false);
        end;

        ResultText := ResponseBody;
        exit(ExtractJsonValue(ResponseBody, 'activity_id', TrackingNo) or ExtractJsonValue(ResponseBody, 'id', TrackingNo));
    end;

    procedure GetLabel(var WhseShptHeader: Record "Warehouse Shipment Header"; var TempBlob: Codeunit "Temp Blob"): Boolean
    begin
        // Bumbal levert (voor zover bekend) geen verzendlabel; niet van toepassing.
        exit(false);
    end;

    procedure GetTracking(var WhseShptHeader: Record "Warehouse Shipment Header"; var TrackingNo: Text; var StatusText: Text): Boolean
    var
        ConnectorSetup: Record "MBT Transport Connector Setup";
        AuthorizationHeader: Text;
        ResponseBody: Text;
        ErrorText: Text;
    begin
        if not ConnectorSetup.Get(ConnectorCodeTok) then
            exit(false);
        TrackingNo := WhseShptHeader."MBT Tracking No.";
        if TrackingNo = '' then
            exit(false);
        if not GetAuthorizationHeader(AuthorizationHeader, ErrorText) then
            exit(false);

        if not HttpClientHelper.GetJson(ConnectorSetup."Base URL" + ActivityEndpointTok + TrackingNo, AuthorizationHeader, ResponseBody, ErrorText) then
            exit(false);

        exit(ExtractJsonValue(ResponseBody, 'status', StatusText));
    end;

    procedure ExportFile(var TempTransportExportBuffer: Record "MBT Transport Export Buffer" temporary): Boolean
    begin
        // Bumbal is een API-connector; bestandsexport is hier niet van toepassing.
        exit(false);
    end;

    procedure ProcessInboundFeedback(): Boolean
    begin
        // Terugkoppeling verloopt via polling of webhook-registratie; exacte vorm nog te
        // bevestigen met Bumbal (open punt #3, Bouwplan §7.2.2).
        exit(false);
    end;

    local procedure BuildActivityRequestBody(WhseShptHeader: Record "Warehouse Shipment Header"): Text
    var
        RequestJson: JsonObject;
        RequestText: Text;
    begin
        RequestJson.Add('reference', WhseShptHeader."No.");
        RequestJson.WriteTo(RequestText);
        exit(RequestText);
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

    local procedure GetAuthorizationHeader(var AuthorizationHeader: Text; var ErrorText: Text): Boolean
    var
        ApiKey: Text;
    begin
        if not TransportCredMgt.GetSecret(ConnectorCodeTok, 'ApiKey', ApiKey) then begin
            ErrorText := CredentialsMissingErr;
            exit(false);
        end;
        AuthorizationHeader := 'Bearer ' + ApiKey;
        exit(true);
    end;

    var
        TransportCredMgt: Codeunit "MBT Transport Cred. Mgt.";
        HttpClientHelper: Codeunit "MBT Http Client Helper";
        ConnectorCodeTok: Label 'BUMBAL', Locked = true;
        ActivitySetEndpointTok: Label '/activity/set', Locked = true;
        ActivityEndpointTok: Label '/activity/', Locked = true;
        SetupMissingErr: Label 'De transportkoppeling %1 is niet (correct) ingericht in Transport Connector Setup.';
        CredentialsMissingErr: Label 'Er is nog geen Bumbal API-key/JWT vastgelegd in Isolated Storage.';
}
