tableextension 52100 "MBT Whse. Shpt. Header Ext" extends "Warehouse Shipment Header"
{
    fields
    {
        field(52100; "MBT Carrier Connector Code"; Code[20])
        {
            Caption = 'Expediteur';
            TableRelation = "MBT Transport Connector Setup".Code where(Active = const(true));
            DataClassification = CustomerContent;

            trigger OnValidate()
            var
                WhseShptLockMgt: Codeunit "MBT Whse Shpt Lock Mgt.";
            begin
                if "MBT Carrier Connector Code" = xRec."MBT Carrier Connector Code" then
                    exit;
                WhseShptLockMgt.CheckNotLocked(Rec);
            end;
        }
        field(52101; "MBT Tracking No."; Text[100])
        {
            Caption = 'Tracking No.';
            DataClassification = CustomerContent;
        }
        field(52102; "MBT Exported"; Boolean)
        {
            Caption = 'Exported';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(52103; "MBT Export Date/Time"; DateTime)
        {
            Caption = 'Export Date/Time';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(52104; "MBT Export Error"; Boolean)
        {
            Caption = 'Export Error';
            DataClassification = CustomerContent;
            Editable = false;
        }
    }
}
