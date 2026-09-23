enum 52102 "MBT Transport Log Status"
{
    Extensible = true;
    Caption = 'Transport Log Status';

    value(0; Success)
    {
        Caption = 'Succes';
    }
    value(1; Error)
    {
        Caption = 'Fout';
    }
    value(2; Warning)
    {
        Caption = 'Waarschuwing';
    }
}
