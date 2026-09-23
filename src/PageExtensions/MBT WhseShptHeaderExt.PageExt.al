pageextension 52100 "MBT Whse Shipment Header Ext." extends "Warehouse Shipment"
{
    layout
    {
        addlast(General)
        {
            field("MBT Carrier Connector Code"; Rec."MBT Carrier Connector Code")
            {
                ApplicationArea = All;
                ToolTip = 'Geeft de expediteur (transporteur-connector) weer waarmee deze verzending wordt verstuurd.';
            }
            field("MBT Tracking No."; Rec."MBT Tracking No.")
            {
                ApplicationArea = All;
                ToolTip = 'Geeft het trackingnummer weer dat door de transporteur is toegekend.';
            }
            field("MBT Exported"; Rec."MBT Exported")
            {
                ApplicationArea = All;
                ToolTip = 'Geeft aan of deze verzending al is geëxporteerd naar de transporteur.';
            }
            field("MBT Export Date/Time"; Rec."MBT Export Date/Time")
            {
                ApplicationArea = All;
                ToolTip = 'Geeft aan wanneer deze verzending is geëxporteerd naar de transporteur.';
            }
            field("MBT Export Error"; Rec."MBT Export Error")
            {
                ApplicationArea = All;
                ToolTip = 'Geeft aan of de laatste exportpoging naar de transporteur is mislukt.';
            }
        }
    }
}
