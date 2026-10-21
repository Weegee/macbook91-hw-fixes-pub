// SPDX-License-Identifier: GPL-2.0-only
/*
 * macbook91_backlight - brightness steps that look even to the eye on the
 * Apple MacBook9,1 panel.
 *
 * intel_backlight is linear in luminance: its lowest five percent hold
 * everything a dim room needs, and desktops that step it in equal parts
 * jump from dark to bright. This module registers a backlight device of type
 * "platform" whose levels are CIE 1976 lightness (L*) and drives
 * intel_backlight with the matching luminance. Desktops prefer platform over
 * raw devices (PowerDevil, systemd), so keys, sliders and automatic
 * brightness all move in perceptually even steps.
 *
 * It needs acpi_backlight=native: with acpi_video0 present, that firmware
 * device would be preferred over this one.
 *
 * CIE 1931 conversion follows cie1931() in drivers/video/backlight/pwm_bl.c.
 */
#include <linux/backlight.h>
#include <linux/dmi.h>
#include <linux/math64.h>
#include <linux/module.h>
#include <linux/workqueue.h>

#define MB91_LEVELS	1000
#define MB91_TARGET	"intel_backlight"
#define MB91_TRIES	120	/* wait up to a minute for i915 */

static struct backlight_device *mb91_bl;
static struct delayed_work mb91_work;
static int mb91_tries;

/*
 * Raw intel_backlight value for lightness level v (0..MB91_LEVELS), i.e.
 * L* = 100 * v / MB91_LEVELS. Luminance Y = L / 903.3 up to L* = 8, else
 * ((L + 16) / 116)^3. Level 0 is off; every other level is at least 1, so
 * the lowest steps stay visible.
 */
static u32 mb91_to_raw(u32 v, u32 max)
{
	u64 l, n, d, raw;

	if (v == 0 || max == 0)
		return 0;
	l = (u64)v * 100;			/* L* times MB91_LEVELS */
	if (l <= 8ULL * MB91_LEVELS) {
		raw = div64_u64((u64)max * l * 10 * 2, 9033ULL * MB91_LEVELS);
	} else {
		n = l + 16ULL * MB91_LEVELS;
		d = 116ULL * MB91_LEVELS;
		raw = mul_u64_u64_div_u64(n * n * n, (u64)max * 2, d * d * d);
	}
	raw = (raw + 1) / 2;			/* round to nearest */
	return clamp_t(u64, raw, 1, max);
}

/* Smallest level whose raw value reaches raw (mb91_to_raw is monotonic). */
static u32 mb91_from_raw(u32 raw, u32 max)
{
	u32 lo = 0, hi = MB91_LEVELS, mid;

	if (raw == 0)
		return 0;
	while (lo < hi) {
		mid = lo + (hi - lo) / 2;
		if (mb91_to_raw(mid, max) < raw)
			lo = mid + 1;
		else
			hi = mid;
	}
	return lo;
}

static int mb91_update_status(struct backlight_device *bd)
{
	struct backlight_device *intel;
	int ret;

	/* Looked up on every change: i915 may re-register its device. */
	intel = backlight_device_get_by_name(MB91_TARGET);
	if (!intel)
		return -ENODEV;
	ret = backlight_device_set_brightness(intel,
		mb91_to_raw(backlight_get_brightness(bd), intel->props.max_brightness));
	put_device(&intel->dev);
	return ret;
}

static int mb91_get_brightness(struct backlight_device *bd)
{
	struct backlight_device *intel;
	u32 raw, max, v = bd->props.brightness;

	intel = backlight_device_get_by_name(MB91_TARGET);
	if (!intel)
		return v;
	raw = intel->props.brightness;
	max = intel->props.max_brightness;
	put_device(&intel->dev);
	/*
	 * Several low levels share a raw value; report the level that was set
	 * as long as intel_backlight still shows it, and follow intel_backlight
	 * when something else has changed it.
	 */
	if (mb91_to_raw(v, max) == raw)
		return v;
	return mb91_from_raw(raw, max);
}

static const struct backlight_ops mb91_ops = {
	.update_status	= mb91_update_status,
	.get_brightness	= mb91_get_brightness,
};

static void mb91_register(struct work_struct *work)
{
	struct backlight_properties props = {
		.type		= BACKLIGHT_PLATFORM,
		.max_brightness	= MB91_LEVELS,
		.scale		= BACKLIGHT_SCALE_NON_LINEAR,
	};
	struct backlight_device *intel, *bd;

	intel = backlight_device_get_by_name(MB91_TARGET);
	if (!intel) {
		if (++mb91_tries < MB91_TRIES)
			schedule_delayed_work(&mb91_work, msecs_to_jiffies(500));
		else
			pr_warn("macbook91_backlight: no %s after %d s; is i915 loaded?\n",
				MB91_TARGET, MB91_TRIES / 2);
		return;
	}
	props.brightness = mb91_from_raw(intel->props.brightness,
					 intel->props.max_brightness);
	put_device(&intel->dev);

	bd = backlight_device_register("macbook91_backlight", NULL, NULL,
				       &mb91_ops, &props);
	if (IS_ERR(bd)) {
		pr_err("macbook91_backlight: register failed: %ld\n", PTR_ERR(bd));
		return;
	}
	mb91_bl = bd;
	pr_info("macbook91_backlight: %d perceptual levels on %s\n",
		MB91_LEVELS, MB91_TARGET);
}

static const struct dmi_system_id mb91_dmi[] = {
	{
		.matches = {
			DMI_EXACT_MATCH(DMI_SYS_VENDOR, "Apple Inc."),
			DMI_EXACT_MATCH(DMI_PRODUCT_NAME, "MacBook9,1"),
		},
	},
	{ }
};
MODULE_DEVICE_TABLE(dmi, mb91_dmi);

static int __init mb91_init(void)
{
	if (!dmi_check_system(mb91_dmi))
		return -ENODEV;
	/* i915 may still be probing when udev loads this module. */
	INIT_DELAYED_WORK(&mb91_work, mb91_register);
	schedule_delayed_work(&mb91_work, 0);
	return 0;
}

static void __exit mb91_exit(void)
{
	cancel_delayed_work_sync(&mb91_work);
	if (mb91_bl)
		backlight_device_unregister(mb91_bl);
}

module_init(mb91_init);
module_exit(mb91_exit);

MODULE_DESCRIPTION("Perceptual (CIE L*) backlight levels for the Apple MacBook9,1");
MODULE_LICENSE("GPL");
#ifdef MB91_VERSION
MODULE_VERSION(MB91_VERSION);
#endif
