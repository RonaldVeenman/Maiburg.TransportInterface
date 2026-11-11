table 52102 "MBT Transport Log"
{
    Caption = 'Transport Log';
    DataClassification = CustomerContent;
    LookupPageId = "MBT Transport Log";
    DrillDownPageId = "MBT Transport Log";

    fields
    {
        field(1; "Entry No."; Integer)
        {
            Caption = 'Entry No.';
            AutoIncrement = true;
        }
        field(2; "Date/Time"; DateTime)
        {
            Caption = 'Date/Time';
        }
        field(3; "Connector Code"; Code[20])
        {
            Caption = 'Connector Code';
            TableRelation = "MBT Transport Connector Setup".Code;
        }
        field(4; "Whse. Shipment No."; Code[20])
        {
            Caption = 'Whse. Shipment No.';
        }
        field(5; Direction; Enum "MBT Transport Log Direction")
        {
            Caption = 'Direction';
        }
        field(6; Status; Enum "MBT Transport Log Status")
        {
            Caption = 'Status';
        }
        field(7; "Message Text"; Text[2048])
        {
            Caption = 'Message Text';
        }
        field(8; "Request Payload"; Blob)
        {
            Caption = 'Request Payload';
        }
        field(9; "Response Payload"; Blob)
        {
            Caption = 'Response Payload';
        }
    }

    keys
    {
        key(PK; "Entry No.")
        {
            Clustered = true;
        }
        key(Lookup; "Connector Code", "Whse. Shipment No.", "Date/Time")
        {
        }
    }
}
