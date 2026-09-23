codeunit 52106 "MBT VanDerWerff Connector" implements "MBT ITransportConnector"
{
    // STUB — zie Bouwplan §7.4: de koppeling met Van der Werff wordt in deze fase alleen
    // voorbereid (inactieve setup-rij + deze stub), niet inhoudelijk gebouwd. Het XML-schema
    // is nog niet vastgesteld (FO-openstaand punt #4). Zodra dit bekend is, wordt deze stub
    // vervangen door een echte implementatie (of aangevuld met "MBT VanDerWerff Api Connector"
    // wanneer Van der Werff overstapt naar een API).

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
    begin
        Error(NotYetImplementedGenericErr);
    end;

    procedure ProcessInboundFeedback(): Boolean
    begin
        Error(NotYetImplementedGenericErr);
    end;

    var
        NotYetImplementedErr: Label 'De koppeling met Van der Werff is nog niet ontwikkeld. Zendingnummer: %1. Neem contact op met de projectleider zodra het XML-schema van Van der Werff is vastgesteld.';
        NotYetImplementedGenericErr: Label 'De koppeling met Van der Werff is nog niet ontwikkeld. Neem contact op met de projectleider zodra het XML-schema van Van der Werff is vastgesteld.';
}
