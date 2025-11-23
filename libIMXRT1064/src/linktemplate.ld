MEMORY
{
    ITCM (rwx) : ORIGIN = itcmBase, LENGTH = itcmSize
    DTCM (rwx) : ORIGIN = dtcmBase, LENGTH = dtcmSize
    OCM (rwx) : ORIGIN = ocmBase, LENGTH = ocmSize
    FLASH (rx) : ORIGIN = imageBase, LENGTH = imageSize
    SDRAM (rwx) : ORIGIN = sdramBase, LENGTH = sdramSize
    NCACHE (rwx) : ORIGIN = ncacheBase, LENGTH = ncacheSize
}

SECTIONS
{
    /**
     * Boot header in flash, must be at 0x70000000
     *  so it's the first section we have here.
     */
    .boot_hdr : ALIGN(4)
    {
        KEEP(*(.boot_hdr*))
    } >FLASH =0xFFFFFFFF
    
    /* XIP Code in here */
    .text : ALIGN(4)
    {
        *(.image_vector_table*)
        *(.text*)
        . = ALIGN(4);
    } >FLASH =0xFFFFFFFF

    /* Read-only data in Flash */
    .rodata : ALIGN(4)
    {
        *(.rodata*)

        /* Section table. This is so the boot code can find each section to initialize RAM */
        . = ALIGN(4);
        __section_table_begin = .;
        LONG(LOADADDR(.dtcm_data));
        LONG(    ADDR(.dtcm_data));
        LONG(  SIZEOF(.dtcm_data));
        LONG(LOADADDR(.dtcm_bss));
        LONG(    ADDR(.dtcm_bss));
        LONG(  SIZEOF(.dtcm_bss));
        LONG(LOADADDR(.itcm_text));
        LONG(    ADDR(.itcm_text));
        LONG(  SIZEOF(.itcm_text));
        LONG(LOADADDR(.ocm_data));
        LONG(    ADDR(.ocm_data));
        LONG(  SIZEOF(.ocm_data));
        LONG(LOADADDR(.sdram_data));
        LONG(    ADDR(.sdram_data));
        LONG(  SIZEOF(.sdram_data));
        LONG(LOADADDR(.ncache_data));
        LONG(    ADDR(.ncache_data));
        LONG(  SIZEOF(.ncache_data));
        __section_table_end = .;
        __section_table_size = __section_table_end - __section_table_begin;
    } >FLASH =0xFFFFFFFF

    /**
     * We've asked the compiler nicely to not generate unwind tables, but it still does.
     * However, with them disabled, it at least doesn't whinge about it when we black hole them.
     */
    /DISCARD/ :
    {
        *(.ARM.extab)
        *(.ARM.exidx)
    }

    /* Code in ITCM, initial values in flash */
    .itcm_text : ALIGN(4)
    {
        *(.itcm_text*)
        . = ALIGN(4);
    } >ITCM AT>FLASH =0xFFFFFFFF

    /* Data in DTCM, should be initialized to zero early by bootloader. */
    .dtcm_bss : AT(0) ALIGN(4)
    {
        *(.bss*)
        . = ALIGN(4);
    } >DTCM

    /* Data in DTCM, initial values in flash */
    .dtcm_data : ALIGN(4)
    {
        *(.data*)
        . = ALIGN(4);
    } >DTCM AT>FLASH =0xFFFFFFFF

    /* Data in OCM, initial values in flash */
    .ocm_data : ALIGN(4)
    {
        *(.ocm_data*)
        . = ALIGN(4);
    } >OCM AT>FLASH =0xFFFFFFFF

    /* Data in SDRAM, initial values in flash */
    .sdram_data : ALIGN(4)
    {
        *(.sdram_data*)
        . = ALIGN(4);
    } >SDRAM AT>FLASH =0xFFFFFFFF

    /* Data in NCACHE region, initial values in flash */
    .ncache_data : ALIGN(4)
    {
        *(.ncache_data*)
        . = ALIGN(4);
    } >NCACHE AT>FLASH =0xFFFFFFFF

    /* Dummy sections to define symbols describing the kernel heap spaces */
    .ocm_heap : ALIGN(4)
    {
        __ocm_heap_begin = .;
        __ocm_heap_size = LENGTH(OCM) - (. - ORIGIN(OCM));
    } >OCM

    .dtcm_heap : ALIGN(4)
    {
        __dtcm_heap_begin = .;
        __dtcm_heap_size = LENGTH(DTCM) - (. - ORIGIN(DTCM)) - stackSize;
    } >DTCM

    /* Dummy section to define where the supervisor stack goes */
    .supervisor_stack : ALIGN(4)
    {
        __supervisor_stack_top = ORIGIN(DTCM) + LENGTH(DTCM);
        __supervisor_stack_bottom = __supervisor_stack_top - stackSize;
    } >DTCM
}