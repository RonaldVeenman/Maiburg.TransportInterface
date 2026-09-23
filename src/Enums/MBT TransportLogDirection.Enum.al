enum 52101 "MBT Transport Log Direction"
{
    Extensible = true;
    Caption = 'Transport Log Direction';

    value(0; Outbound)
    {
        Caption = 'Uitgaand';
    }
    value(1; Inbound)
    {
        Caption = 'Inkomend';
    }
}
