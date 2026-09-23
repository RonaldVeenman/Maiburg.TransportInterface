table 52101 "MBT Transport Export Buffer"
{
    Caption = 'Transport Export Buffer';
    DataClassification = CustomerContent;
    TableType = Temporary;

    fields
    {
        field(1; "Whse. Shipment No."; Code[20])
        {
            Caption = 'Whse. Shipment No.';
            TableRelation = "Warehouse Shipment Header"."No.";
        }
        field(2; Selected; Boolean)
        {
            Caption = 'Selected';
        }
        field(3; "Carrier Connector Code"; Code[20])
        {
            Caption = 'Expediteur';
            TableRelation = "MBT Transport Connector Setup".Code;
        }
        field(4; "Customer Name"; Text[100])
        {
            Caption = 'Customer Name';
        }
        field(5; "Total Qty. (Colli)"; Decimal)
        {
            Caption = 'Total Qty. (Colli)';
            DecimalPlaces = 0 : 5;
        }
        field(6; "Total Weight"; Decimal)
        {
            Caption = 'Total Weight';
            DecimalPlaces = 0 : 5;
        }
        field(7; "Shipment Date"; Date)
        {
            Caption = 'Shipment Date';
        }
        field(8; Exported; Boolean)
        {
            Caption = 'Exported';
        }
        field(9; "Export Date Time"; DateTime)
        {
            Caption = 'Export Date Time';
        }
        field(10; "Tracking No."; Text[100])
        {
            Caption = 'Tracking No.';
        }
        field(11; "Error Text"; Text[250])
        {
            Caption = 'Error Text';
        }
    }

    keys
    {
        key(PK; "Whse. Shipment No.")
        {
            Clustered = true;
        }
        key(ConnectorCode; "Carrier Connector Code")
        {
        }
    }
}
