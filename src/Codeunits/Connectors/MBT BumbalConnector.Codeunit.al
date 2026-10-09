codeunit 52104 "MBT Bumbal Connector" implements "MBT ITransportConnector"
{
    // Bumbal (FreightLive) Activity-API — geverifieerd tegen de officiële API-documentatie
    // ("Koppelen via API met Bumbal", api-docs.freightlive.eu). Authenticatie gebeurt via
    // e-mail/wachtwoord (sign-in), niet via een API-key/JWT-Bearer-header zoals eerder
    // aangenomen in het Bouwplan §7.2. De resulterende sessietoken wordt meegestuurd in een
    // custom header "Token" en vervalt na 2 uur inactiviteit. Zendingen worden via "links"
    // (link_id + provider_name) uniek herkenbaar geregistreerd, zoals door Bumbal aanbevolen.
    // De vorm van track & trace-terugkoppeling (polling vs. webhook) is nog te bevestigen met
    // Bumbal (open punt #3); dit is voorlopig uitgewerkt als polling via GetTracking.

    procedure CreateShipment(var WhseShptHeader: Record "Warehouse Shipment Header"; var ResultText: Text; var TrackingNo: Text): Boolean
    var
        ConnectorSetup: Record "MBT Transport Connector Setup";
        SessionToken: Text;
        RequestBody: Text;
        ResponseBody: Text;
        ErrorText: Text;
        RequestHeaders: Dictionary of [Text, Text];
    begin
        if not ConnectorSetup.Get(ConnectorCodeTok) then begin
            ResultText := StrSubstNo(SetupMissingErr, ConnectorCodeTok);
            exit(false);
        end;

        if not GetSessionToken(SessionToken, ErrorText) then begin
            ResultText := ErrorText;
            exit(false);
        end;

        RequestBody := BuildActivityRequestBody(WhseShptHeader);
        RequestHeaders := BuildJsonAcceptHeaders();

        // Zonder expliciete Accept-header antwoordt Bumbal met XML i.p.v. JSON.
        if not HttpClientHelper.PostJson(ConnectorSetup."Base URL" + ActivitySetEndpointTok, RequestBody, SessionTokenHeaderNameTok, SessionToken, RequestHeaders, ResponseBody, ErrorText) then begin
            ResultText := ErrorText;
            exit(false);
        end;

        ResultText := ResponseBody;
        exit(ExtractActivityId(ResponseBody, TrackingNo));
    end;

    procedure GetLabel(var WhseShptHeader: Record "Warehouse Shipment Header"; var TempBlob: Codeunit "Temp Blob"): Boolean
    begin
        // Bumbal levert geen verzendlabel; niet van toepassing.
        exit(false);
    end;

    procedure GetTracking(var WhseShptHeader: Record "Warehouse Shipment Header"; var TrackingNo: Text; var StatusText: Text): Boolean
    var
        ConnectorSetup: Record "MBT Transport Connector Setup";
        SessionToken: Text;
        RequestBody: Text;
        ResponseBody: Text;
        ErrorText: Text;
        RequestJson: JsonObject;
        FiltersJson: JsonObject;
        RequestHeaders: Dictionary of [Text, Text];
    begin
        if not ConnectorSetup.Get(ConnectorCodeTok) then
            exit(false);
        TrackingNo := WhseShptHeader."MBT Tracking No.";
        if not GetSessionToken(SessionToken, ErrorText) then
            exit(false);

        // Activities worden opgehaald via PUT /activity met filters, niet via GET op een
        // per-activity-URL (zie "Activiteiten ophalen" in de API-documentatie).
        FiltersJson.Add('id', TrackingNo);
        RequestJson.Add('filters', FiltersJson);
        RequestJson.WriteTo(RequestBody);
        RequestHeaders := BuildJsonAcceptHeaders();

        if not HttpClientHelper.PutJson(ConnectorSetup."Base URL" + ActivityEndpointTok, RequestBody, SessionTokenHeaderNameTok, SessionToken, RequestHeaders, ResponseBody, ErrorText) then
            exit(false);

        exit(ExtractFirstItemValue(ResponseBody, 'status_name', StatusText));
    end;

    procedure ExportFile(var TempTransportExportBuffer: Record "MBT Transport Export Buffer" temporary): Boolean
    begin
        // Bumbal is een API-connector; bestandsexport is hier niet van toepassing.
        exit(false);
    end;

    procedure ProcessInboundFeedback(): Boolean
    begin
        // Terugkoppeling verloopt via polling (GetTracking) of webhook-registratie; exacte
        // vorm nog te bevestigen met Bumbal (open punt #3).
        exit(false);
    end;

    /// <summary>
    /// Maakt de standaard credential-placeholders (Email, Password) aan in MBT Transport Conn.
    /// Credent. zodra de Bumbal-connector wordt ingericht, zodat de beheerder direct weet welke
    /// waarden nog moeten worden ingevoerd via de pagina Transport Connector Credentials.
    /// </summary>
    procedure EnsureRequiredCredentialsExist()
    begin
        EnsureCredentialExists('Email', EmailDescriptionTxt);
        EnsureCredentialExists('Password', PasswordDescriptionTxt);
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

    local procedure BuildActivityRequestBody(WhseShptHeader: Record "Warehouse Shipment Header"): Text
    var
        SalesHeader: Record "Sales Header";
        RequestJson: JsonObject;
        LinksArray: JsonArray;
        LinkObject: JsonObject;
        CapacitiesArray: JsonArray;
        SalesOrderNo: Code[20];
        TotalQty: Decimal;
        TotalWeight: Decimal;
        RequestText: Text;
    begin
        RequestJson.Add('nr', WhseShptHeader."No.");
        RequestJson.Add('reference', WhseShptHeader."No.");
        RequestJson.Add('activity_type_name', ActivityTypeNameTok);
        // Placeholder totdat het tijdvenster (time_slots) met Bumbal is bevestigd (open punt
        // #7); de "duration" (in minuten) is wel verplicht bij aanmaak.
        RequestJson.Add('duration', DefaultDurationMinutesTok);

        // "capacities" (ActivityModel/CapacityModel in de Bumbal-swagger) i.p.v. losse
        // quantity/weight-velden, die niet in het schema bestaan. capacity_type_name moet nog
        // worden afgestemd met de capaciteitstypes zoals ingericht in de Bumbal-tenant (open
        // punt #7); "weight"/"quantity" zijn hier een aanname.
        GetShipmentTotals(WhseShptHeader."No.", TotalQty, TotalWeight);
        CapacitiesArray.Add(BuildCapacityJson('weight', TotalWeight, 'KG'));
        CapacitiesArray.Add(BuildCapacityJson('quantity', TotalQty, 'amount'));
        RequestJson.Add('capacities', CapacitiesArray);

        // Eén magazijnverzending komt van één verkooporder; adres/opmerkingen/communicatie
        // komen van die order. package_lines komt van de magazijnverzendingsregels zelf (niet
        // van de volledige verkooporder), anders wordt bij deelleveringen een veel te hoog
        // gewicht/aantal doorgegeven.
        SalesOrderNo := FindSalesOrderNo(WhseShptHeader);
        if SalesOrderNo <> '' then
            if SalesHeader.Get(SalesHeader."Document Type"::Order, SalesOrderNo) then begin
                RequestJson.Add('address', BuildAddressJson(SalesHeader));
                AddRemarksAndCommunication(SalesHeader, RequestJson);
            end;
        RequestJson.Add('package_lines', BuildPackageLinesJson(WhseShptHeader));

        // Aanbevolen door Bumbal: activiteiten herkenbaar maken via een links-object, zodat
        // dezelfde zending later via filters.links opnieuw gevonden kan worden.
        LinkObject.Add('link_id', WhseShptHeader."No.");
        LinkObject.Add('provider_name', ProviderNameTok);
        LinksArray.Add(LinkObject);
        RequestJson.Add('links', LinksArray);

        RequestJson.WriteTo(RequestText);
        exit(RequestText);
    end;

    /// <summary>Telt colli (Qty. to Ship (Base)) en gewicht van alle regels van deze magazijnverzending op, zoals in TransportExportMgt.GetTotals.</summary>
    local procedure GetShipmentTotals(WhseShptNo: Code[20]; var TotalQty: Decimal; var TotalWeight: Decimal)
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

    /// <summary>Bouwt één CapacityModel-object (bv. gewicht of aantal) zoals gebruikt in "capacities" op Activity- en package_line-niveau.</summary>
    local procedure BuildCapacityJson(CapacityTypeName: Text; CapacityValue: Decimal; UomName: Text): JsonObject
    var
        CapacityJson: JsonObject;
    begin
        CapacityJson.Add('capacity_type_name', CapacityTypeName);
        CapacityJson.Add('capacity_value', CapacityValue);
        CapacityJson.Add('capacity_value_uom_name', UomName);
        exit(CapacityJson);
    end;

    /// <summary>Zoekt het verkooporder-nummer achter deze magazijnverzending.</summary>
    local procedure FindSalesOrderNo(WhseShptHeader: Record "Warehouse Shipment Header"): Code[20]
    var
        WhseShptLine: Record "Warehouse Shipment Line";
    begin
        WhseShptLine.SetRange("No.", WhseShptHeader."No.");
        WhseShptLine.SetRange("Source Document", WhseShptLine."Source Document"::"Sales Order");
        if WhseShptLine.FindFirst() then
            exit(WhseShptLine."Source No.");
        exit('');
    end;

    /// <summary>Bouwt het adres-object (AddressModel) uit het ship-to van de verkooporder.</summary>
    local procedure BuildAddressJson(SalesHeader: Record "Sales Header"): JsonObject
    var
        AddressJson: JsonObject;
    begin
        AddressJson.Add('name_1', SalesHeader."Ship-to Name");
        AddressJson.Add('name_2', SalesHeader."Ship-to Name 2");
        AddressJson.Add('street_1', SalesHeader."Ship-to Address");
        AddressJson.Add('street_2', SalesHeader."Ship-to Address 2");
        AddressJson.Add('zipcode', SalesHeader."Ship-to Post Code");
        AddressJson.Add('city', SalesHeader."Ship-to City");
        AddressJson.Add('iso_country', SalesHeader."Ship-to Country/Region Code");
        exit(AddressJson);
    end;

    /// <summary>Voegt remarks (referentie) en communication (phone_nr/email) toe uit de verkooporder.</summary>
    local procedure AddRemarksAndCommunication(SalesHeader: Record "Sales Header"; var RequestJson: JsonObject)
    var
        CommunicationJson: JsonObject;
        RemarksText: Text;
    begin
        if SalesHeader."Your Reference" <> '' then
            RemarksText := SalesHeader."Your Reference"
        else
            RemarksText := SalesHeader."External Document No.";
        if RemarksText <> '' then
            RequestJson.Add('remarks', RemarksText);

        if (SalesHeader."Ship-to Phone No." <> '') or (SalesHeader."Sell-to E-Mail" <> '') then begin
            CommunicationJson.Add('phone_nr', SalesHeader."Ship-to Phone No.");
            CommunicationJson.Add('email', SalesHeader."Sell-to E-Mail");
            RequestJson.Add('communication', CommunicationJson);
        end;
    end;

    /// <summary>Bouwt de package_lines-array (PackageLineModel) uit de regels van déze magazijnverzending (niet de volledige verkooporder), zodat bij deelleveringen alleen het werkelijk verzonden aantal wordt doorgegeven. Er zijn geen item_no/weight/unit_of_measure-velden in dit schema; het itemnummer gaat via "barcode". Gewicht wordt hier bewust niet nogmaals meegegeven: Bumbal telt de capacities van package_lines op bij de shipment-brede "capacities", dus anders wordt het totaalgewicht dubbel geteld.</summary>
    local procedure BuildPackageLinesJson(WhseShptHeader: Record "Warehouse Shipment Header"): JsonArray
    var
        WhseShptLine: Record "Warehouse Shipment Line";
        PackageLinesArray: JsonArray;
        PackageLineJson: JsonObject;
        LineCapacitiesArray: JsonArray;
    begin
        WhseShptLine.SetRange("No.", WhseShptHeader."No.");
        WhseShptLine.SetFilter("Qty. to Ship", '<>%1', 0);
        if WhseShptLine.FindSet() then
            repeat
                Clear(PackageLineJson);
                Clear(LineCapacitiesArray);
                PackageLineJson.Add('barcode', WhseShptLine."Item No.");
                PackageLineJson.Add('description', WhseShptLine.Description);
                PackageLineJson.Add('nr_of_packages', WhseShptLine."Qty. to Ship");
                // Cubage is al het totaalvolume van de regel, niet een volume per stuk.
                LineCapacitiesArray.Add(BuildCapacityJson('volume', WhseShptLine.Cubage, 'M3'));
                PackageLineJson.Add('capacities', LineCapacitiesArray);
                PackageLinesArray.Add(PackageLineJson);
            until WhseShptLine.Next() = 0;
        exit(PackageLinesArray);
    end;

    /// <summary>Leest additional_data.activity_info.id uit de respons van POST /activity/set.</summary>
    local procedure ExtractActivityId(ResponseBody: Text; var ActivityId: Text): Boolean
    var
        ResponseJson: JsonObject;
        AdditionalDataToken: JsonToken;
        ActivityInfoToken: JsonToken;
        IdToken: JsonToken;
    begin
        if not ResponseJson.ReadFrom(ResponseBody) then
            exit(false);
        if not ResponseJson.Get('additional_data', AdditionalDataToken) then
            exit(false);
        if not AdditionalDataToken.AsObject().Get('activity_info', ActivityInfoToken) then
            exit(false);
        if not ActivityInfoToken.AsObject().Get('id', IdToken) then
            exit(false);
        if IdToken.AsValue().IsNull() then
            exit(false);
        ActivityId := IdToken.AsValue().AsText();
        exit(true);
    end;

    /// <summary>Leest een veld uit het eerste element van items[] (respons van PUT /activity).</summary>
    local procedure ExtractFirstItemValue(ResponseBody: Text; JsonKeyName: Text; var Value: Text): Boolean
    var
        ResponseJson: JsonObject;
        ItemsToken: JsonToken;
        ItemsArray: JsonArray;
        FirstItemToken: JsonToken;
        ValueToken: JsonToken;
    begin
        if not ResponseJson.ReadFrom(ResponseBody) then
            exit(false);
        if not ResponseJson.Get('items', ItemsToken) then
            exit(false);
        ItemsArray := ItemsToken.AsArray();
        if ItemsArray.Count() = 0 then
            exit(false);
        ItemsArray.Get(0, FirstItemToken);
        if not FirstItemToken.AsObject().Get(JsonKeyName, ValueToken) then
            exit(false);
        if ValueToken.AsValue().IsNull() then
            exit(false);
        Value := ValueToken.AsValue().AsText();
        exit(true);
    end;

    /// <summary>Accept-headers zodat Bumbal JSON teruggeeft i.p.v. het XML-standaardformaat (Accept-Encoding bewust weggelaten: AL decomprimeert gzip niet zelf).</summary>
    local procedure BuildJsonAcceptHeaders(): Dictionary of [Text, Text]
    var
        Headers: Dictionary of [Text, Text];
    begin
        Headers.Add('Accept', 'application/json');
        Headers.Add('Accept-Language', 'en-US,en;q=0.8');
        exit(Headers);
    end;

    /// <summary>Hergebruikt een nog geldige sessietoken, of meldt opnieuw aan (sign-in) als deze ontbreekt/verlopen is.</summary>
    local procedure GetSessionToken(var SessionToken: Text; var ErrorText: Text): Boolean
    var
        ExpirationText: Text;
        Expiration: DateTime;
    begin
        if TransportCredMgt.GetSecret(ConnectorCodeTok, 'SessionToken', SessionToken) and (SessionToken <> '') then
            if TransportCredMgt.GetSecret(ConnectorCodeTok, 'SessionTokenExpiration', ExpirationText) then
                if Evaluate(Expiration, ExpirationText) then
                    if Expiration > CurrentDateTime() then
                        exit(true);

        exit(SignIn(SessionToken, ErrorText));
    end;

    /// <summary>Meldt aan via POST /authenticate/sign-in (e-mail/wachtwoord) en cachet de sessietoken.</summary>
    local procedure SignIn(var SessionToken: Text; var ErrorText: Text): Boolean
    var
        ConnectorSetup: Record "MBT Transport Connector Setup";
        Email: Text;
        Password: Text;
        RequestJson: JsonObject;
        RequestText: Text;
        ResponseBody: Text;
        ResponseJson: JsonObject;
        JsonToken: JsonToken;
        SignInHeaders: Dictionary of [Text, Text];
    begin
        if not ConnectorSetup.Get(ConnectorCodeTok) then begin
            ErrorText := StrSubstNo(SetupMissingErr, ConnectorCodeTok);
            exit(false);
        end;
        if not (TransportCredMgt.GetSecret(ConnectorCodeTok, 'Email', Email) and TransportCredMgt.GetSecret(ConnectorCodeTok, 'Password', Password)) then begin
            ErrorText := CredentialsMissingErr;
            exit(false);
        end;

        RequestJson.Add('email', Email);
        RequestJson.Add('password', Password);
        RequestJson.WriteTo(RequestText);
        SignInHeaders := BuildJsonAcceptHeaders();

        if not HttpClientHelper.PostJson(ConnectorSetup."Base URL" + SignInEndpointTok, RequestText, '', '', SignInHeaders, ResponseBody, ErrorText) then
            exit(false);

        if not ResponseJson.ReadFrom(ResponseBody) or not ResponseJson.Get('token', JsonToken) or JsonToken.AsValue().IsNull() then begin
            ErrorText := StrSubstNo(TokenResponseErr, ResponseBody);
            exit(false);
        end;
        SessionToken := JsonToken.AsValue().AsText();

        TransportCredMgt.SetSecret(ConnectorCodeTok, 'SessionToken', SessionToken);
        // De sessietoken zelf kent geen vaste geldigheidsduur (vervalt na 2 uur inactiviteit);
        // hier wordt uit voorzorg ruim vóór dat moment (105 min.) al opnieuw aangemeld.
        TransportCredMgt.SetSecret(ConnectorCodeTok, 'SessionTokenExpiration', Format(CurrentDateTime() + 6300000));
        exit(true);
    end;

    var
        TransportCredMgt: Codeunit "MBT Transport Cred. Mgt.";
        HttpClientHelper: Codeunit "MBT Http Client Helper";
        ConnectorCodeTok: Label 'BUMBAL', Locked = true;
        SignInEndpointTok: Label '/authenticate/sign-in', Locked = true;
        ActivitySetEndpointTok: Label '/activity/set', Locked = true;
        ActivityEndpointTok: Label '/activity', Locked = true;
        SessionTokenHeaderNameTok: Label 'Token', Locked = true;
        ProviderNameTok: Label 'business_central', Locked = true;
        ActivityTypeNameTok: Label 'dropoff', Locked = true;
        DefaultDurationMinutesTok: Label '15', Locked = true;
        SetupMissingErr: Label 'De transportkoppeling %1 is niet (correct) ingericht in Transport Connector Setup.';
        CredentialsMissingErr: Label 'Er zijn nog geen Bumbal-credentials (Email/Password) vastgelegd in Isolated Storage.';
        TokenResponseErr: Label 'Kon geen geldige sessietoken uit het Bumbal-authenticatie-antwoord lezen: %1';
        EmailDescriptionTxt: Label 'Bumbal inlog-e-mailadres';
        PasswordDescriptionTxt: Label 'Bumbal inlogwachtwoord';
}
