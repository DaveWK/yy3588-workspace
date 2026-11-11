# youyeetoo YY3588 firmware: own bt0 (oreboot fork) -> TF-A BL31 -> EDK2
# (edk2-rk3588 fork). Sources are the git submodules under firmware/.
#
#   make yy3588-bt0        bt0 (SRAM) and its BootROM idblock, no DDR init
#   make yy3588            image with bt0 only (bt0 stops: own DDR init is WIP)
#   make yy3588-rkbin-ddr  DEV ONLY: rkbin DDR init + bt0 + BL31 + EDK2 image,
#                          the one that boots today
#   make yy3588-loader     DEV ONLY: MaskROM USB loaders (rkdeveloptool db)
#   make yy3588-clean
#
# YY3588_TARGET=DEBUG|RELEASE (EDK2), YY3588_OPEN_TFA=true|false (BL31 from
# the TF-A submodule, or rkbin's prebuilt BL31), YY3588_IDBLOCK_FEATURES
# (bt0 features of the idblock boot image; add ,diag for the PMIC/rail dump).

YY3588_TARGET ?= DEBUG
YY3588_OPEN_TFA ?= true
YY3588_TREE ?= firmware/edk2-rk3588
YY3588_OUT ?= out/yy3588
YY3588_BOARD := firmware/oreboot/src/mainboard/youyeetoo/yy3588
YY3588_BT0_DIR := $(YY3588_BOARD)/bt0
YY3588_BT0_TGT := $(abspath $(YY3588_OUT))/target
YY3588_IMG := YY3588_skeleton_$(YY3588_TARGET).img
YY3588_RKBIN_IMG := YY3588_rkbinddr_$(YY3588_TARGET).img
YY3588_IDBLOCK_FEATURES ?= stepping-stone
YY3588_USB_FEATURES := stepping-stone,usb-loader
YY3588_DIAG_FEATURES := stepping-stone,usb-loader,diag
YY3588_COMMA := ,
YY3588_DDR_BIN ?= $(YY3588_TREE)/misc/rkbin/bin/rk35/rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.24.bin
YY3588_CARGO := env -u RUSTUP_TOOLCHAIN -u RUSTFLAGS cargo +1.99.0
YY3588_TOOLS_TGT := $(abspath $(YY3588_OUT))/target/host
YY3588_IDB := CARGO_TARGET_DIR=$(YY3588_TOOLS_TGT) $(YY3588_CARGO) run -q --release --locked --manifest-path $(YY3588_BOARD)/tools/rk-idblock/Cargo.toml --
YY3588_LDR := CARGO_TARGET_DIR=$(YY3588_TOOLS_TGT) $(YY3588_CARGO) run -q --release --locked --manifest-path $(YY3588_BOARD)/tools/rk-loader/Cargo.toml --
YY3588_EDK2 = cd $(YY3588_TREE) && IDBLOCK_BIN=$(abspath $(1)) BL32_BIN=none \
	./build.sh -d yy3588 -r $(YY3588_TARGET) --open-tfa $(YY3588_OPEN_TFA)
YY3588_DEV_BANNER := @echo "*** DEV ONLY: contains the Rockchip rkbin DDR init blob (licence: rkbin LICENSE) ***"

.PHONY: help yy3588 yy3588-bt0 yy3588-rkbin-idblock yy3588-rkbin-ddr yy3588-loader yy3588-clean check-sources

help:
	@sed -n '4,13p' Makefile

check-sources:
	@test -x $(YY3588_TREE)/build.sh && test -f $(YY3588_BT0_DIR)/Cargo.toml || \
		{ echo "submodules missing: git submodule update --init --recursive" >&2; exit 1; }

# yy3588_bt0 <cargo features> <output .bin>
define yy3588_bt0
	cd $(YY3588_BT0_DIR) && CARGO_TARGET_DIR=$(YY3588_BT0_TGT)/$(subst $(YY3588_COMMA),-,$(or $(1),sram)) \
		$(YY3588_CARGO) build --release --locked $(if $(1),--features $(1))
	mkdir -p $(YY3588_OUT)
	aarch64-linux-gnu-objcopy -O binary \
		$(YY3588_BT0_TGT)/$(subst $(YY3588_COMMA),-,$(or $(1),sram))/aarch64-unknown-none-softfloat/release/yy3588-bt0 $(2)
endef

yy3588-bt0: check-sources
	$(call yy3588_bt0,,$(YY3588_OUT)/yy3588-bt0.bin)
	$(YY3588_IDB) pack --soc rk3588 --init $(YY3588_OUT)/yy3588-bt0.bin --out $(YY3588_OUT)/idblock.bin
	$(YY3588_IDB) verify $(YY3588_OUT)/idblock.bin
	cd $(YY3588_OUT) && sha256sum yy3588-bt0.bin idblock.bin

yy3588: yy3588-bt0
	$(call YY3588_EDK2,$(YY3588_OUT)/idblock.bin)
	cp $(YY3588_TREE)/RK3588_NOR_FLASH.img $(YY3588_OUT)/$(YY3588_IMG)
	cd $(YY3588_OUT) && sha256sum $(YY3588_IMG) | tee $(YY3588_IMG).sha256

$(YY3588_OUT)/rkbin-ddr.bin: | check-sources
	@test -f $(YY3588_DDR_BIN) || { echo "no rkbin DDR init at $(YY3588_DDR_BIN)" >&2; exit 1; }
	mkdir -p $(YY3588_OUT)
	cp $(YY3588_DDR_BIN) $@

yy3588-rkbin-idblock: $(YY3588_OUT)/rkbin-ddr.bin
	$(YY3588_DEV_BANNER)
	$(call yy3588_bt0,$(YY3588_IDBLOCK_FEATURES),$(YY3588_OUT)/yy3588-bt0-dram.bin)
	$(YY3588_IDB) pack --soc rk3588 --init $(YY3588_OUT)/rkbin-ddr.bin \
		--boot $(YY3588_OUT)/yy3588-bt0-dram.bin --out $(YY3588_OUT)/idblock-rkbinddr.bin
	$(YY3588_IDB) verify $(YY3588_OUT)/idblock-rkbinddr.bin

yy3588-rkbin-ddr: yy3588-rkbin-idblock
	$(call YY3588_EDK2,$(YY3588_OUT)/idblock-rkbinddr.bin)
	cp $(YY3588_TREE)/RK3588_NOR_FLASH.img $(YY3588_OUT)/$(YY3588_RKBIN_IMG)
	cd $(YY3588_OUT) && sha256sum yy3588-bt0-dram.bin idblock-rkbinddr.bin $(YY3588_RKBIN_IMG) \
		| tee $(YY3588_RKBIN_IMG).sha256
	$(YY3588_DEV_BANNER)

yy3588-loader: $(YY3588_OUT)/rkbin-ddr.bin
	$(YY3588_DEV_BANNER)
	$(call yy3588_bt0,$(YY3588_USB_FEATURES),$(YY3588_OUT)/yy3588-bt0-usb.bin)
	$(call yy3588_bt0,$(YY3588_DIAG_FEATURES),$(YY3588_OUT)/yy3588-bt0-diag.bin)
	$(call yy3588_bt0,stepping-stone,$(YY3588_OUT)/yy3588-bt0-dram.bin)
	$(YY3588_LDR) pack --chip rk3588 --471 $(YY3588_OUT)/rkbin-ddr.bin \
		--472 $(YY3588_OUT)/yy3588-bt0-usb.bin --out $(YY3588_OUT)/YY3588_rkbinddr_fastboot_loader.bin
	$(YY3588_LDR) pack --chip rk3588 --471 $(YY3588_OUT)/rkbin-ddr.bin \
		--472 $(YY3588_OUT)/yy3588-bt0-diag.bin --out $(YY3588_OUT)/YY3588_rkbinddr_draminfo_loader.bin
	$(YY3588_LDR) pack --chip rk3588 --471 $(YY3588_OUT)/rkbin-ddr.bin \
		--472 $(YY3588_OUT)/yy3588-bt0-dram.bin --out $(YY3588_OUT)/YY3588_rkbinddr_boot_loader.bin
	$(YY3588_LDR) verify $(YY3588_OUT)/YY3588_rkbinddr_draminfo_loader.bin
	$(YY3588_LDR) verify $(YY3588_OUT)/YY3588_rkbinddr_fastboot_loader.bin
	cd $(YY3588_OUT) && sha256sum yy3588-bt0-usb.bin yy3588-bt0-diag.bin yy3588-bt0-dram.bin \
		YY3588_rkbinddr_fastboot_loader.bin YY3588_rkbinddr_draminfo_loader.bin YY3588_rkbinddr_boot_loader.bin
	$(YY3588_DEV_BANNER)

yy3588-clean:
	rm -rf $(YY3588_OUT)
	[ ! -x $(YY3588_TREE)/build.sh ] || { cd $(YY3588_TREE) && ./build.sh -C; }
