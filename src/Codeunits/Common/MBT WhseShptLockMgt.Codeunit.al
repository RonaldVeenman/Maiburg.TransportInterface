codeunit 52102 "MBT Whse Shpt Lock Mgt."
{
    /// <summary>
    /// Bepaalt of het Expediteur-veld op een magazijnverzending vergrendeld is, doordat er
    /// al een magazijnpick voor deze verzending bestaat (FO §7.7).
    /// </summary>
    procedure IsLocked(WhseShptHeader: Record "Warehouse Shipment Header"): Boolean
    var
        WhseActivityLine: Record "Warehouse Activity Line";
    begin
        WhseActivityLine.SetRange("Activity Type", WhseActivityLine."Activity Type"::Pick);
        WhseActivityLine.SetRange("Whse. Document Type", WhseActivityLine."Whse. Document Type"::Shipment);
        WhseActivityLine.SetRange("Whse. Document No.", WhseShptHeader."No.");
        exit(not WhseActivityLine.IsEmpty());
    end;

    /// <summary>Geeft een foutmelding als de expediteur niet meer gewijzigd mag worden.</summary>
    procedure CheckNotLocked(WhseShptHeader: Record "Warehouse Shipment Header")
    begin
        if IsLocked(WhseShptHeader) then
            Error(CarrierLockedErr, WhseShptHeader."No.");
    end;

    var
        CarrierLockedErr: Label 'Er is al een magazijnpick aangemaakt voor deze verzending (%1). De expediteur kan niet meer worden gewijzigd.';
}
