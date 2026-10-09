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

        RequestBody := BuildShipmentRequestBody(WhseShptHeader, ConnectorSetup);

        if not HttpClientHelper.PostJson(ConnectorSetup."Base URL" + ShipmentsEndpointTok, RequestBody, 'Bearer ' + AccessToken, ResponseBody, ErrorText) then begin
            // Token kan toch verlopen zijn (bv. ingetrokken): één keer opnieuw aanmelden en herhalen.
            if IsNotAuthorized(ErrorText) and RefreshOrAuthenticate(AccessToken, ErrorText) then
                if HttpClientHelper.PostJson(ConnectorSetup."Base URL" + ShipmentsEndpointTok, RequestBody, 'Bearer ' + AccessToken, ResponseBody, ErrorText) then
                    exit(ParseShipmentResponse(ResponseBody, TrackingNo, ResultText));
            // Verzonden bericht meegeven in het logboek, zodat afwijzingen (bv. 400) te analyseren zijn.
            ResultText := StrSubstNo(RequestSentTxt, ErrorText, RequestBody);
            exit(false);
        end;

        if not ParseShipmentResponse(ResponseBody, TrackingNo, ResultText) then
            exit(false);

        exit(true);
    end;

    /// <summary>
    /// Haalt het verzendlabel (PDF) op; dit is het aanroeppunt van de connector-interface.
    /// Werkt in twee stappen (DHL eCommerce API-gids, hoofdstuk 4):
    /// 1. Find labels: GET /labels?trackerCodeFilter=... (of ?shipmentId=... als het opgeslagen
    ///    nummer een zendings-ID/GUID is); lukt dat niet, dan ?orderReferenceFilter=... met het
    ///    nummer van de magazijnverzending (dat is bij het aanmelden als orderReference meegestuurd).
    /// 2. Get label: GET /labels/{labelId} met Accept: application/pdf.
    /// Bij meerdere gevonden labels wordt het eerste label gedownload.
    /// De vorige werkwijze via POST /labels/multi staat nog in GetLabelViaMulti.
    /// </summary>
    procedure GetLabel(var WhseShptHeader: Record "Warehouse Shipment Header"; var TempBlob: Codeunit "Temp Blob"): Boolean
    var
        ConnectorSetup: Record "MBT Transport Connector Setup";
        AccessToken: Text;
        LabelId: Text;
        ErrorText: Text;
        LabelError: Text;
        AdditionalHeaders: Dictionary of [Text, Text];
    begin
        if not ConnectorSetup.Get(ConnectorCodeTok) then
            exit(false);
        if WhseShptHeader."MBT Tracking No." = '' then
            exit(false);
        if not GetAccessToken(AccessToken, ErrorText) then
            Error(ErrorText);

        if not FindLabelId(ConnectorSetup, AccessToken, WhseShptHeader, LabelId, ErrorText) then
            Error(LabelsRetrievalFailedErr, ErrorText);

        AdditionalHeaders.Add('Accept', 'application/pdf');
        if HttpClientHelper.GetForBinary(ConnectorSetup."Base URL" + LabelsBaseEndpointTok + '/' + LabelId, 'Authorization', 'Bearer ' + AccessToken, AdditionalHeaders, TempBlob, LabelError) then
            exit(true);

        // Token kan tussen zoeken en downloaden verlopen zijn: één keer opnieuw aanmelden en herhalen.
        if IsNotAuthorized(LabelError) then
            if RefreshOrAuthenticate(AccessToken, ErrorText) then
                if HttpClientHelper.GetForBinary(ConnectorSetup."Base URL" + LabelsBaseEndpointTok + '/' + LabelId, 'Authorization', 'Bearer ' + AccessToken, AdditionalHeaders, TempBlob, LabelError) then
                    exit(true);

        Error(LabelsRetrievalFailedErr, LabelError);
    end;

    /// <summary>Zoekt het label-ID via Find labels: eerst op trackercode of zendings-ID, daarna op orderReference.</summary>
    local procedure FindLabelId(ConnectorSetup: Record "MBT Transport Connector Setup"; var AccessToken: Text; WhseShptHeader: Record "Warehouse Shipment Header"; var LabelId: Text; var ErrorText: Text): Boolean
    var
        TrackingNo: Text;
    begin
        TrackingNo := WhseShptHeader."MBT Tracking No.";
        if IsGuidText(TrackingNo) then begin
            if FindLabelIdWithFilter(ConnectorSetup, AccessToken, 'shipmentId', TrackingNo, LabelId, ErrorText) then
                exit(true);
        end else
            if FindLabelIdWithFilter(ConnectorSetup, AccessToken, 'trackerCodeFilter', TrackingNo, LabelId, ErrorText) then
                exit(true);

        exit(FindLabelIdWithFilter(ConnectorSetup, AccessToken, 'orderReferenceFilter', WhseShptHeader."No.", LabelId, ErrorText));
    end;

    /// <summary>Roept GET /labels?{FilterName}={FilterValue} aan en geeft het labelId van het eerste resultaat terug; vernieuwt eenmalig het token bij een 401.</summary>
    local procedure FindLabelIdWithFilter(ConnectorSetup: Record "MBT Transport Connector Setup"; var AccessToken: Text; FilterName: Text; FilterValue: Text; var LabelId: Text; var ErrorText: Text): Boolean
    var
        Uri: Codeunit Uri;
        Url: Text;
        ResponseBody: Text;
        ResponseArray: JsonArray;
        LabelToken: JsonToken;
        IdToken: JsonToken;
        AdditionalHeaders: Dictionary of [Text, Text];
        RefreshError: Text;
    begin
        LabelId := '';
        Url := ConnectorSetup."Base URL" + LabelsBaseEndpointTok + '?' + FilterName + '=' + Uri.EscapeDataString(FilterValue);
        AdditionalHeaders.Add('Accept', 'application/json');

        if not HttpClientHelper.GetJson(Url, 'Authorization', 'Bearer ' + AccessToken, AdditionalHeaders, ResponseBody, ErrorText) then begin
            if not IsNotAuthorized(ErrorText) then
                exit(false);
            if not RefreshOrAuthenticate(AccessToken, RefreshError) then begin
                ErrorText := RefreshError;
                exit(false);
            end;
            if not HttpClientHelper.GetJson(Url, 'Authorization', 'Bearer ' + AccessToken, AdditionalHeaders, ResponseBody, ErrorText) then
                exit(false);
        end;

        if not ResponseArray.ReadFrom(ResponseBody) or (ResponseArray.Count() = 0) then begin
            ErrorText := StrSubstNo(NoLabelFoundErr, FilterName, FilterValue);
            exit(false);
        end;

        ResponseArray.Get(0, LabelToken);
        if not LabelToken.AsObject().Get('labelId', IdToken) then begin
            ErrorText := StrSubstNo(NoLabelFoundErr, FilterName, FilterValue);
            exit(false);
        end;
        LabelId := IdToken.AsValue().AsText();
        exit(LabelId <> '');
    end;

    /// <summary>
    /// Vorige werkwijze: haalt het PDF-label op via POST /labels/multi (Accept: application/pdf).
    /// Eerst op basis van het trackingnummer (shipmentTrackerCodes, of shipmentIds als het
    /// opgeslagen nummer een zendings-ID/GUID is). Lukt dat niet, dan worden via
    /// GET /labels?orderReferenceFilter de label-ID's van deze magazijnverzending opgezocht
    /// (orderReference = nr. magazijnverzending). Wordt niet meer aangeroepen door GetLabel.
    /// </summary>
    procedure GetLabelViaMulti(var WhseShptHeader: Record "Warehouse Shipment Header"; var TempBlob: Codeunit "Temp Blob"): Boolean
    var
        ConnectorSetup: Record "MBT Transport Connector Setup";
        AccessToken: Text;
        RequestBody: Text;
        ErrorText: Text;
        LabelsError: Text;
        LabelIds: JsonArray;
        AdditionalHeaders: Dictionary of [Text, Text];
    begin
        if not ConnectorSetup.Get(ConnectorCodeTok) then
            exit(false);
        if WhseShptHeader."MBT Tracking No." = '' then
            exit(false);
        if not GetAccessToken(AccessToken, ErrorText) then
            Error(ErrorText);

        AdditionalHeaders.Add('Accept', 'application/pdf');

        RequestBody := BuildLabelsRequestBodyByTracking(WhseShptHeader."MBT Tracking No.");
        if HttpClientHelper.PostJsonForBinary(ConnectorSetup."Base URL" + LabelsEndpointTok, RequestBody, 'Authorization', 'Bearer ' + AccessToken, AdditionalHeaders, TempBlob, LabelsError) then
            exit(true);

        // Token kan verlopen zijn: één keer opnieuw aanmelden en herhalen.
        if IsNotAuthorized(LabelsError) then
            if RefreshOrAuthenticate(AccessToken, ErrorText) then
                if HttpClientHelper.PostJsonForBinary(ConnectorSetup."Base URL" + LabelsEndpointTok, RequestBody, 'Authorization', 'Bearer ' + AccessToken, AdditionalHeaders, TempBlob, LabelsError) then
                    exit(true);

        if FindLabelIdsByOrderReference(ConnectorSetup, AccessToken, WhseShptHeader."No.", LabelIds, ErrorText) then begin
            RequestBody := BuildLabelsRequestBodyByLabelIds(LabelIds);
            if HttpClientHelper.PostJsonForBinary(ConnectorSetup."Base URL" + LabelsEndpointTok, RequestBody, 'Authorization', 'Bearer ' + AccessToken, AdditionalHeaders, TempBlob, LabelsError) then
                exit(true);
        end;

        Error(LabelsRetrievalFailedErr, LabelsError);
    end;

    local procedure BuildLabelsRequestBodyByTracking(TrackingNo: Text): Text
    var
        RequestJson: JsonObject;
        CodesArray: JsonArray;
        RequestText: Text;
    begin
        CodesArray.Add(TrackingNo);
        if IsGuidText(TrackingNo) then
            RequestJson.Add('shipmentIds', CodesArray)
        else
            RequestJson.Add('shipmentTrackerCodes', CodesArray);
        RequestJson.WriteTo(RequestText);
        exit(RequestText);
    end;

    local procedure BuildLabelsRequestBodyByLabelIds(LabelIds: JsonArray): Text
    var
        RequestJson: JsonObject;
        RequestText: Text;
    begin
        RequestJson.Add('labelIds', LabelIds);
        RequestJson.WriteTo(RequestText);
        exit(RequestText);
    end;

    /// <summary>Zoekt de label-ID's bij de orderReference (Find labels, GET /labels?orderReferenceFilter=).</summary>
    local procedure FindLabelIdsByOrderReference(ConnectorSetup: Record "MBT Transport Connector Setup"; AccessToken: Text; OrderReference: Text; var LabelIds: JsonArray; var ErrorText: Text): Boolean
    var
        ResponseBody: Text;
        ResponseArray: JsonArray;
        LabelToken: JsonToken;
        IdToken: JsonToken;
        i: Integer;
    begin
        Clear(LabelIds);
        if not HttpClientHelper.GetJson(ConnectorSetup."Base URL" + LabelsBaseEndpointTok + '?orderReferenceFilter=' + OrderReference, 'Bearer ' + AccessToken, ResponseBody, ErrorText) then
            exit(false);
        if not ResponseArray.ReadFrom(ResponseBody) then
            exit(false);

        for i := 0 to ResponseArray.Count() - 1 do begin
            ResponseArray.Get(i, LabelToken);
            if LabelToken.AsObject().Get('labelId', IdToken) then
                LabelIds.Add(IdToken.AsValue().AsText());
        end;
        exit(LabelIds.Count() > 0);
    end;

    local procedure IsGuidText(Value: Text): Boolean
    begin
        exit((StrLen(Value) = 36) and (CopyStr(Value, 9, 1) = '-') and (CopyStr(Value, 14, 1) = '-'));
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

    local procedure BuildShipmentRequestBody(WhseShptHeader: Record "Warehouse Shipment Header"; ConnectorSetup: Record "MBT Transport Connector Setup"): Text
    var
        SalesHeader: Record "Sales Header";
        RequestJson: JsonObject;
        OptionsArray: JsonArray;
        OptionObject: JsonObject;
        PiecesArray: JsonArray;
        SalesOrderNo: Code[20];
        RequestText: Text;
    begin
        RequestJson.Add('shipmentId', CreateShipmentId());
        RequestJson.Add('orderReference', WhseShptHeader."No.");
        RequestJson.Add('accountId', ConnectorSetup."Account ID");

        Clear(SalesHeader);
        SalesOrderNo := FindSalesOrderNo(WhseShptHeader);
        if SalesOrderNo <> '' then
            if not SalesHeader.Get(SalesHeader."Document Type"::Order, SalesOrderNo) then
                Clear(SalesHeader);
        RequestJson.Add('receiver', BuildReceiverJson(SalesHeader));
        RequestJson.Add('shipper', BuildShipperJson());

        // "Geen handtekening voor ontvangst" (DOOR); beschikbaar voor zakelijke en particuliere
        // ontvangers. Maak dit instelbaar per zending/klant zodra meerdere DHL-opties
        // ondersteund moeten worden. "options" is verplicht (lege array = geen opties).
        OptionObject.Add('key', DoorOptionTok);
        OptionsArray.Add(OptionObject);
        RequestJson.Add('options', OptionsArray);

        PiecesArray.Add(BuildPieceJson(WhseShptHeader."No."));
        RequestJson.Add('pieces', PiecesArray);

        RequestJson.WriteTo(RequestText);
        exit(RequestText);
    end;

    /// <summary>Zoekt het verkooporder-nummer achter deze magazijnverzending (zie ook MBT Bumbal Connector).</summary>
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

    /// <summary>Een ontvanger met contactpersoon wordt als zakelijk beschouwd (bedrijfsnaam + contactpersoon).</summary>
    local procedure IsBusinessReceiver(SalesHeader: Record "Sales Header"): Boolean
    begin
        exit(SalesHeader."Ship-to Contact" <> '');
    end;

    local procedure BuildReceiverJson(SalesHeader: Record "Sales Header"): JsonObject
    var
        ReceiverJson: JsonObject;
        CompanyName: Text;
        PersonName: Text;
        FirstName: Text;
        LastName: Text;
    begin
        if IsBusinessReceiver(SalesHeader) then begin
            CompanyName := SalesHeader."Ship-to Name";
            PersonName := SalesHeader."Ship-to Contact";
        end else
            PersonName := SalesHeader."Ship-to Name";
        SplitPersonName(PersonName, FirstName, LastName);

        ReceiverJson.Add('name', BuildNameJson(FirstName, LastName, CompanyName));
        ReceiverJson.Add('address', BuildAddressJson(SalesHeader."Ship-to Address", SalesHeader."Ship-to City", SalesHeader."Ship-to Post Code", SalesHeader."Ship-to Country/Region Code", CompanyName <> ''));
        ReceiverJson.Add('email', SalesHeader."Sell-to E-Mail");
        ReceiverJson.Add('phoneNumber', SalesHeader."Ship-to Phone No.");
        exit(ReceiverJson);
    end;

    local procedure BuildShipperJson(): JsonObject
    var
        CompanyInformation: Record "Company Information";
        ShipperJson: JsonObject;
    begin
        CompanyInformation.Get();
        ShipperJson.Add('name', BuildNameJson('', '', CompanyInformation.Name));
        ShipperJson.Add('address', BuildAddressJson(CompanyInformation.Address, CompanyInformation.City, CompanyInformation."Post Code", CompanyInformation."Country/Region Code", true));
        ShipperJson.Add('email', CompanyInformation."E-Mail");
        ShipperJson.Add('phoneNumber', CompanyInformation."Phone No.");
        exit(ShipperJson);
    end;

    local procedure BuildNameJson(FirstName: Text; LastName: Text; CompanyName: Text): JsonObject
    var
        NameJson: JsonObject;
    begin
        if FirstName <> '' then
            NameJson.Add('firstName', FirstName);
        if LastName <> '' then
            NameJson.Add('lastName', LastName);
        if CompanyName <> '' then
            NameJson.Add('companyName', CompanyName);
        exit(NameJson);
    end;

    /// <summary>Splitst een BC-adresregel ("Straatnaam 12A") in straat/huisnummer/toevoeging op het eerste cijfer.</summary>
    local procedure BuildAddressJson(FullAddress: Text; City: Text; PostCode: Text; CountryCode: Code[10]; IsBusiness: Boolean): JsonObject
    var
        AddressJson: JsonObject;
        Street: Text;
        HouseNo: Text;
        Addition: Text;
    begin
        SplitStreetAndNumber(FullAddress, Street, HouseNo, Addition);
        AddressJson.Add('countryCode', GetIsoCountryCode(CountryCode));
        // DHL verwacht een postcode zonder spaties (bv. "3542AD", niet "3542 AD").
        AddressJson.Add('postalCode', UpperCase(DelChr(PostCode, '=', ' ')));
        AddressJson.Add('city', City);
        AddressJson.Add('street', Street);
        AddressJson.Add('number', HouseNo);
        if Addition <> '' then
            AddressJson.Add('addition', Addition);
        AddressJson.Add('isBusiness', IsBusiness);
        exit(AddressJson);
    end;

    /// <summary>
    /// Geeft de ISO 3166-1 alpha-2 landcode. In BC is de landcode van het eigen land vaak leeg;
    /// dan wordt het land uit de bedrijfsgegevens gebruikt, en anders Nederland. Een lege
    /// landcode leidt bij DHL tot "capabilities_retrieve_empty".
    /// </summary>
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

    local procedure SplitPersonName(FullName: Text; var FirstName: Text; var LastName: Text)
    var
        SpacePos: Integer;
    begin
        FullName := DelChr(FullName, '<>');
        SpacePos := StrPos(FullName, ' ');
        if SpacePos = 0 then begin
            FirstName := FullName;
            LastName := '';
        end else begin
            FirstName := CopyStr(FullName, 1, SpacePos - 1);
            LastName := CopyStr(FullName, SpacePos + 1);
        end;
    end;

    local procedure SplitStreetAndNumber(FullAddress: Text; var Street: Text; var HouseNo: Text; var Addition: Text)
    var
        DigitsTok: Label '0123456789', Locked = true;
        Position: Integer;
        EndPosition: Integer;
    begin
        Street := DelChr(FullAddress, '<>');
        HouseNo := '';
        Addition := '';
        for Position := 1 to StrLen(FullAddress) do
            if StrPos(DigitsTok, CopyStr(FullAddress, Position, 1)) > 0 then begin
                Street := DelChr(CopyStr(FullAddress, 1, Position - 1), '<>');
                EndPosition := Position;
                while (EndPosition <= StrLen(FullAddress)) and (StrPos(DigitsTok, CopyStr(FullAddress, EndPosition, 1)) > 0) do
                    EndPosition += 1;
                HouseNo := CopyStr(FullAddress, Position, EndPosition - Position);
                Addition := DelChr(CopyStr(FullAddress, EndPosition), '<>');
                exit;
            end;
    end;

    local procedure BuildPieceJson(WhseShptNo: Code[20]): JsonObject
    var
        PieceJson: JsonObject;
        TotalQty: Decimal;
        TotalWeight: Decimal;
        PieceWeight: Decimal;
        Quantity: Integer;
    begin
        GetShipmentTotals(WhseShptNo, TotalQty, TotalWeight);
        Quantity := Round(TotalQty, 1, '=');
        if Quantity < 1 then
            Quantity := 1;

        // Bij DHL is "weight" het gewicht per collo (en de maximale grootte/gewicht hangt af van
        // het parcelType); het totaalgewicht moet dus over het aantal colli worden verdeeld.
        PieceWeight := Round(TotalWeight / Quantity, 0.01);

        PieceJson.Add('parcelType', GetParcelType(PieceWeight));
        PieceJson.Add('quantity', Quantity);
        if PieceWeight > 0 then
            PieceJson.Add('weight', PieceWeight);
        exit(PieceJson);
    end;

    /// <summary>Bepaalt het DHL-parcelType op basis van het gewicht per collo (endpoint /parcel-types, zakelijke zendingen vanuit NL).</summary>
    local procedure GetParcelType(Weight: Decimal): Text
    begin
        // Alleen deze sleutels bestaan bij DHL; een onbekende waarde (bv. "LARGE") of een
        // gewicht buiten het bereik van het type geeft "capabilities_retrieve_empty".
        if Weight <= 10 then
            exit('SMALL');
        if Weight <= 20 then
            exit('SMALL_MEDIUM');
        if Weight <= 31 then
            exit('MEDIUM');
        exit('PALLET');
    end;

    /// <summary>Telt colli (Qty. to Ship (Base)) en gewicht van alle regels van deze magazijnverzending op.</summary>
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
                TotalWeight += WhseShptLine.Weight;
            until WhseShptLine.Next() = 0;
    end;

    local procedure CreateShipmentId(): Text
    begin
        exit(DelChr(Format(CreateGuid()), '=', '{}'));
    end;

    /// <summary>Leest het trackingnummer uit de respons van POST /shipments: shipmentTrackerCode, anders trackerCode van het eerste collo, anders shipmentId.</summary>
    local procedure ParseShipmentResponse(ResponseBody: Text; var TrackingNo: Text; var ResultText: Text): Boolean
    var
        ResponseJson: JsonObject;
        JsonToken: JsonToken;
        PiecesArray: JsonArray;
    begin
        ResultText := ResponseBody;
        if ExtractJsonValue(ResponseBody, 'shipmentTrackerCode', TrackingNo) then
            exit(true);

        if ResponseJson.ReadFrom(ResponseBody) then
            if ResponseJson.Get('pieces', JsonToken) and JsonToken.IsArray() then begin
                PiecesArray := JsonToken.AsArray();
                if PiecesArray.Count() > 0 then begin
                    PiecesArray.Get(0, JsonToken);
                    if JsonToken.AsObject().Get('trackerCode', JsonToken) then begin
                        TrackingNo := JsonToken.AsValue().AsText();
                        exit(true);
                    end;
                end;
            end;

        exit(ExtractJsonValue(ResponseBody, 'shipmentId', TrackingNo));
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

    /// <summary>DHL antwoordt met key "not_authorized" als het toegangstoken ontbreekt of verlopen is.</summary>
    local procedure IsNotAuthorized(ErrorText: Text): Boolean
    begin
        exit(ErrorText.Contains('not_authorized'));
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

        // Een DHL-toegangstoken is ca. 15 minuten geldig (accessTokenExpiration is een unix-
        // timestamp); daarom wordt het hier maximaal 10 minuten hergebruikt. Na afloop wordt
        // met het refresh-token een nieuw token opgehaald.
        TransportCredMgt.SetSecret(ConnectorCodeTok, 'AccessTokenExpiration', Format(CurrentDateTime() + 600000));

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
        LabelsBaseEndpointTok: Label '/labels', Locked = true;
        LabelsEndpointTok: Label '/labels/multi', Locked = true;
        TrackTraceEndpointTok: Label '/track-trace/', Locked = true;
        DoorOptionTok: Label 'DOOR', Locked = true;
        DefaultCountryCodeTok: Label 'NL', Locked = true;
        SetupMissingErr: Label 'De transportkoppeling %1 is niet (correct) ingericht in Transport Connector Setup.';
        CredentialsMissingErr: Label 'Er zijn nog geen DHL-credentials (UserId/ApiKey) vastgelegd in Isolated Storage.';
        TokenResponseErr: Label 'Kon geen geldig accessToken uit het DHL-authenticatie-antwoord lezen: %1';
        RequestSentTxt: Label '%1 | Verzonden bericht: %2';
        LabelsRetrievalFailedErr: Label 'Kon het verzendlabel niet ophalen bij DHL: %1';
        NoLabelFoundErr: Label 'DHL heeft geen label gevonden (%1 = %2).';
        UserIdDescriptionTxt: Label 'DHL API-gebruikers-ID';
        ApiKeyDescriptionTxt: Label 'DHL API-sleutel';
}
