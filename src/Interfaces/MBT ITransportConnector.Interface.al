/// <summary>
/// Generieke contract voor alle transporteur-connectors (DHL, Bumbal, Claassen, Van der Werff).
/// Zie Bouwplan_Koppeling_Transporteurs_AL.md §4.5.
/// </summary>
interface "MBT ITransportConnector"
{
    /// <summary>Meldt een magazijnverzending aan bij de transporteur (API-connectors).</summary>
    procedure CreateShipment(var WhseShptHeader: Record "Warehouse Shipment Header"; var ResultText: Text; var TrackingNo: Text): Boolean;

    /// <summary>Haalt het verzendlabel op (alleen relevant voor bv. DHL).</summary>
    procedure GetLabel(var WhseShptHeader: Record "Warehouse Shipment Header"; var TempBlob: Codeunit "Temp Blob"): Boolean;

    /// <summary>Bevraagt de actuele track en trace-status.</summary>
    procedure GetTracking(var WhseShptHeader: Record "Warehouse Shipment Header"; var TrackingNo: Text; var StatusText: Text): Boolean;

    /// <summary>Exporteert een gebundeld bestand voor bestandconnectors (bv. Claassen).</summary>
    procedure ExportFile(var TempTransportExportBuffer: Record "MBT Transport Export Buffer" temporary): Boolean;

    /// <summary>Verwerkt inkomende terugkoppeling (terugkoppelbestand/webhook/polling).</summary>
    procedure ProcessInboundFeedback(): Boolean;
}
