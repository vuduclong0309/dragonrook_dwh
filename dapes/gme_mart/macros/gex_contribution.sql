{% macro gex_contribution(gamma_col, oi_col, spot_col, option_type_col) %}
{#
    Dollar GEX per 1% spot move.
    Formula: gamma * OI * 100 * spot^2 * 0.01 * sign
    Sign convention: call=+1 (dealer short gamma), put=-1
    This is a CONVENTION, not observable dealer positioning.

    Adapted from Shopee item-profile Schema-as-Object / UDF pattern.
    Single source of truth for GEX calc across all models.

    Usage:
        {{ gex_contribution('gamma', 'open_interest', 'spot', 'option_type') }}
#}
COALESCE({{ gamma_col }}, 0)
    * COALESCE({{ oi_col }}, 0)
    * 100
    * POWER({{ spot_col }}, 2)
    * 0.01
    * CASE WHEN {{ option_type_col }} = 'call' THEN 1 ELSE -1 END
{% endmacro %}
